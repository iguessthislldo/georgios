.global ih_irq0
.type ih_irq0, @function
ih_irq0:
    cli
    pushal // Push EAX, ECX, EDX, EBX, original ESP, EBP, ESI, and EDI
    call irq0_handle
    popal
    sti
    iret 

