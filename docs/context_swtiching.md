# Context Switching

## `iret`

On a x86\_32 CPU, the `iret` instruction uses the stack to transition the CPU
from one state to another. It does this by popping new values for the `eip`,
`cs`, and `eflags` registers from the stack in that order. If the `cs` selector
is for a different ring, then `iret` will also pop new values for the `esp` and
`ss` registers from the stack in that order.

## Specific Resources Used

- [Alex Dzoba OS Interrupts](https://alex.dzyoba.com/blog/os-interrupts/)

- [Stackoverflow Question: Switching to User-mode using iret](https://stackoverflow.com/questions/6892421/switching-to-user-mode-using-iret)

- [JamesM's kernel development tutorials part 10](https://web.archive.org/web/20160326062442/http://jamesmolloy.co.uk/tutorial\_html/10.-User%20Mode.html)

- [Skelix OS tutorial part 4](http://skelix.net/skelixos/tutorial04\_en.html)
