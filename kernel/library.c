#include "library.h"

size_t strlen(const char * string) {
    size_t l = 0;
    while (string[l]) { l++; }
	return l;
}

void * memset(void * pointer, i1 value, size_t number) {
    for (size_t i = 0; i < number; i++) {
        ((i1*) pointer)[i] = value;
    }
    return pointer;
}

void * memcpy(void * dest, const void * src, size_t size) {
    u1 * d = dest;
    const u1 * s = src;
    for (size_t i = 0; i < size; i++) {
        *(d++) = *(s++);
    }
    return dest;
}

bool isspace(char c) {
    return c == ' ' || c == '\n' || c == '\t' || c == '\v' || c == '\f' || c == '\r';
}

char * strcpy(char * dest, const char * src) {
    size_t i = 0;
    do dest[i] = src[i]; while (src[i++]);
	return dest;
}
