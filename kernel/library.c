#include "library.h"

u4 strlen(const char * string) {
    u4 l = 0;
    while (string[l]) { l++; }
	return l;
}

void * memset(void * pointer, i1 value, u4 number) {
    for (u4 i = 0; i < number; i++) {
        ((i1*) pointer)[i] = value;
    }
    return pointer;
}

void * memcpy(void * dest, const void * src, u4 size) {
    u1 * d = dest;
    const u1 * s = src;
    for (u4 i = 0; i < size; i++) {
        *(d++) = *(s++);
    }
    return dest;
}

