#include <stdint.h>
#include <stddef.h>

#include "string.h"

size_t strlen(const char* string)
{
	size_t l = 0;
	while (string[l]) {
		l++;
    }
	return l;
}

void * memset(void * pointer, int8_t value, size_t number) {
    for (size_t i = 0; i < number; i++) {
        ((uint8_t *) pointer)[i] = value;
    }
    return pointer;
}
