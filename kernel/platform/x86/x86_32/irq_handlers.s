.global ih_irq0
.type ih_irq0, @function
ih_irq0:
    cli
    pushal // Push EAX, ECX, EDX, EBX, original ESP, EBP, ESI, and EDI
    call irq0_handle
.global irq0_return
irq0_return:
    popal
    sti
    iret 

