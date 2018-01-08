#include <library.h>

struct Frame_Context_struct {
    u1 max_level;
    u4 frame_count;
    u4 frame_size;
    u1 * frame_info;
    void * begin;
};
typedef struct Frame_Context_struct Frame_Context;

void * allocate_frames(Frame_Context fc, u4 n);
void deallocate_pages(Frame_Context fc, void * begin);

