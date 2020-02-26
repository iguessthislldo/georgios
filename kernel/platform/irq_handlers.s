.global ih_irq0
.type ih_irq0, @function
ih_irq0:
    pushal // Push EAX, ECX, EDX, EBX, original ESP, EBP, ESI, and EDI
    call irq0_handle
.global irq0_return
irq0_return:
    popal
    iret

.global ih_irq1
.type ih_irq1, @function
ih_irq1:
    cli
    pushal // Push EAX, ECX, EDX, EBX, original ESP, EBP, ESI, and EDI
    call irq1_handle
    popal
    iret
