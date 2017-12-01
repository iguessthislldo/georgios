#include "library.h"

u32 strlen(const char * string) {
    u32 l = 0;
    while (string[l]) { l++; }
	return l;
}

void * memset(void * pointer, i8 value, u32 number) {
    for (u32 i = 0; i < number; i++) {
        ((i8*) pointer)[i] = value;
    }
    return pointer;
}
