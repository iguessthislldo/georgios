#ifndef GEORGIOS_BIOS_INT_TIME_H
#define GEORGIOS_BIOS_INT_TIME_H

typedef unsigned time_t;

#define time georgios_bios_int_time
extern time_t time(time_t * arg);

#endif
