//  DVIDEO.ASM
extern "C" {
void home_cursor(void);
uchar get_char_attr(void) ;
void mark_cursor_line(unsigned row, uchar attr) ;
void get_vsize(void) ;
void select_video_seg(unsigned vseg) ;
unsigned get_video_seg(void) ;
void clear_display(uchar cattr) ;
void dgotoxy(unsigned x, unsigned y) ;
void dprintc(unsigned x, unsigned y, uchar attr, char outchr) ;
void dprints(unsigned x, unsigned y, uchar attr, char* outstr) ;
void hide_cursor(void);
unsigned get_key(void);
int  key_hit(void);
}

