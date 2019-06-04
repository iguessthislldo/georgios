/* =======================================================================
 * PS/2 Keyboard Driver
 * =======================================================================
 * References:
 * http://www.flingos.co.uk/docs/reference/PS2-Keyboards/
 * https://wiki.osdev.org/"8042"_PS/2_Controller
 */

#include "ps2.h"

#include <kernel.h>
#include <print.h>

#include "io.h"
#include "ps2_scan_codes.h"

// IO Ports
#define DATA_PORT 0x60
#define STATUS_PORT 0x64 // In for status, out for command

// Status Register Masks
#define OUT_BUFFER_FULL 1
#define IN_BUFFER_FULL 2
#define IN_TYPE 8 // Type in input buffer
#define IN_TYPE_DATA 0
#define IN_TYPE_COMMAND 8
#define LOCK 16
#define TX_TIMEOUT 32
#define RX_TIMEOUT 64

// Commands
#define READ_CFG 0x20 // Then Read Byte from Data Port
#define WRITE_CFG 0x60 // Then Write Byte to Command Port
#define DISABLE_PORT2 0xA7
#define ENABLE_PORT2 0xA8
#define DISABLE_PORT1 0xAD
#define ENABLE_PORT1 0xAE
#define CONTROLLER_TEST 0xAA
#define PORT1_TEST 0xAB
#define PORT2_TEST 0xA9
#define WRITE_TO_PORT2_NEXT 0xD4

#define PORT1_INT_ENABLED 1
#define PORT2_INT_ENABLED 2
#define TRANSLATION 128

#define ACK 0xFA
#define NACK 0xFE
#define RESET 0xFF
#define CONTROLLER_TEST_SUCCESS 0x55
#define PORT_TEST_SUCCESS 0x00

#define WAIT_TIME 1000
#define WAIT for (int _i = 0; _i < WAIT_TIME; _i++) { asm ("nop"); }

bool ps2_enabled = false;
bool ps2_dual_channel = false;
bool ps2_port1 = false;
bool ps2_port2 = false;

static inline bool ps2_wait_ready(const char * message) {
    // Wait until we can send something to the controller
    for (int i = 0; i < WAIT_TIME * 100; i++) {
        if (!(in1(STATUS_PORT) & IN_BUFFER_FULL)) {
            return false;
        }
    }
    print_string("PS/2 send timeout: ");
    print_string(message);
    print_char('\n');
    return true;
}

u1 ps2_receive() {
    for (int i = 0; i < WAIT_TIME * 100; i++) {
        // Check Read Buffer Status until it has a value
        if (in1(STATUS_PORT) & OUT_BUFFER_FULL) {
            return in1(DATA_PORT);
        }
    }
    print_string("PS/2 Receive Timeout\n");
    return 0;
}

bool ps2_send(bool port, u1 value) {
    if (port) {
        if (ps2_wait_ready("Port 2 Flag")) return false;
        out1(STATUS_PORT, WRITE_TO_PORT2_NEXT);
    }
    if (ps2_wait_ready("On Send Data")) return false;
    out1(DATA_PORT, value);
    return true;
}

#define READY_OR_FAIL(msg) \
if (ps2_wait_ready((msg))) { \
    return; \
}
void ps2_init() {
    // TODO: Use ACPI to test for PS/2 Controller. Return if missing
#if 0

    // Disable Ports
    READY_OR_FAIL("Disable Port 1");
    out1(STATUS_PORT, DISABLE_PORT1);
    READY_OR_FAIL("Disable Port 2");
    out1(STATUS_PORT, DISABLE_PORT2);

    // Flush Buffer
    in1(DATA_PORT);

    // Read Config
    READY_OR_FAIL("1st Read Config");
    out1(STATUS_PORT, READ_CFG);
    WAIT
    u1 config = ps2_receive();

    // Test for 2nd Port
    ps2_dual_channel = !(config & (1 << 5));
    if (ps2_dual_channel) {
        print_string("PS/2 Second Port Detected\n");
    }

    // Disable Interupts and Translation
    config &= !(PORT1_INT_ENABLED | PORT2_INT_ENABLED | TRANSLATION);

    print_format("config: {x}\n", config);

    // Write Config
    READY_OR_FAIL("1st Write Config Flag");
    out1(STATUS_PORT, WRITE_CFG);
    WAIT
    READY_OR_FAIL("1st Write Config Data");
    out1(DATA_PORT, config);

    u1 response;

    // Test Controller
    READY_OR_FAIL("Test Controller");
    out1(STATUS_PORT, CONTROLLER_TEST);
    WAIT
    response = ps2_receive();
    if (response != CONTROLLER_TEST_SUCCESS) {
        print_format("PS/2 Controller Test Failure: {x}\n", response);
        return;
    }

    // Test Ports
    bool port1_test_succeeded;
    bool port2_test_succeeded = false;
    READY_OR_FAIL("Test Port 1");
    out1(STATUS_PORT, PORT1_TEST);
    WAIT
    response = ps2_receive();
    port1_test_succeeded = response == PORT_TEST_SUCCESS;
    if (ps2_dual_channel) {
        READY_OR_FAIL("Test Port 2");
        out1(STATUS_PORT, PORT2_TEST);
        WAIT
        response = ps2_receive();
        port2_test_succeeded = response == PORT_TEST_SUCCESS;
    }
    if (!port1_test_succeeded && !port2_test_succeeded) {
        print_string("PS/2 Ports Test Failed\n");
        return;
    }

    // Enable Interrupts and Translation
    READY_OR_FAIL("2nd Read Config");
    out1(STATUS_PORT, READ_CFG);
    WAIT
    config = ps2_receive();
    config |= (PORT1_INT_ENABLED | TRANSLATION);
    if (port2_test_succeeded) {
        config |= PORT2_INT_ENABLED;
    }
    READY_OR_FAIL("2nd Write Config Flag");
    out1(STATUS_PORT, WRITE_CFG);
    READY_OR_FAIL("2nd Write Config Data");
    out1(STATUS_PORT, config);

    // Enable Ports and Reset Devices
    if (port1_test_succeeded) {
        // Enable 1st Port
        READY_OR_FAIL("Enable 1st Port");
        out1(STATUS_PORT, ENABLE_PORT1);
        // Try to Reset Device on the 1st Port
        if (ps2_send(false, RESET)) {
            response = ps2_receive();
            if (response == ACK) {
                ps2_port1 = true;
            } else {
                print_format("Reset Device at PS/2 Port 1 Failed, "
                    "Response: {x}\n", response);
            }
        } else {
            print_format("Reset Device at PS/2 Port 1 Send Failed\n");
        }
    }
    if (port2_test_succeeded) {
        // Enable 2nd Port
        READY_OR_FAIL("Enable 2nd Port");
        out1(STATUS_PORT, ENABLE_PORT2);
        // Try to Reset Device on the 2nd Port
        if (ps2_send(true, RESET)) {
            response = ps2_receive();
            if (response == ACK) {
                ps2_port2 = true;
            } else {
                print_format("Reset Device at PS/2 Port 2 Failed, "
                    "Response: {x}\n", response);
            }
        } else {
            print_format("Reset Device at PS/2 Port 2 Send Failed\n");
        }
    }

    print_format(
        "PS/2 Initialization is Done:\n"
        "    Device on Port 1 is {s}.\n",
        ps2_port1 ? "present" : "not present"
    );
    if (ps2_dual_channel) {
        print_format("    Device on Port 2 is {s}.\n", ps2_port2 ? "present" : "not present");
    }
#endif
    ps2_enabled = true;
}

bool right_shift_is_pressed = false;
bool left_shift_is_pressed = false;
bool alt_is_pressed = false;
bool control_is_pressed = false;

void ps2_print() {
    u1 code = ps2_receive();
    if (!code) return;
    switch(code) {
    case Key_Left_Shift_Pressed:
        left_shift_is_pressed = true;
        break;
    case Key_Right_Shift_Pressed:
        right_shift_is_pressed = true;
        break;
    case Key_Left_Shift_Released:
        left_shift_is_pressed = false;
        break;
    case Key_Right_Shift_Released:
        right_shift_is_pressed = false;
        break;
    case Key_Left_Alt_Pressed:
        alt_is_pressed = true;
        break;
    case Key_Left_Alt_Released:
        alt_is_pressed = false;
        break;
    case Key_Left_Control_Pressed:
        control_is_pressed = true;
        break;
    case Key_Left_Control_Released:
        control_is_pressed = false;
        break;
    }
    bool shifted = right_shift_is_pressed || left_shift_is_pressed;
    char c = ps2_scan_code_to_char(code);
    if (c) {
        if (shifted && alt_is_pressed && c == 'D') {
            print_dragon();
            return;
        }
        if (shifted && alt_is_pressed && c == 'P') {
            shutdown();
            return;
        }
        if (!shifted && c >= 'A' && c <= 'Z') c += 'a' - 'A';
        print_char(c);
    }
}
