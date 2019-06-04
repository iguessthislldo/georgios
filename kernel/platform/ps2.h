/* ===========================================================================
 * PS/2 Keyboard Driver
 * ===========================================================================
 */

#ifndef PS2_HEADER
#define PS2_HEADER

#include <basic_types.h>

#include "ps2_scan_codes.h"

bool ps2_enabled;
bool ps2_dual_channel;
bool ps2_port1;
bool ps2_port2;

void ps2_init();
u1 ps2_receive();

void ps2_print();

#endif
