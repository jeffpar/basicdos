//********************************************************************
//  INTSUM.HPP - Data and function declarations for INTSUM app.       
//                                                                    
//  Written by:   Daniel D. Miller                                    
//                                                                    
//  Last Update:  10-14-95 12:30pm                                    
//                                                                    
//  Compile with makefile                                             
//                                                                    
//********************************************************************

#define  cur_version "1.6"

#define Version   "   Interrupt Summary Version " cur_version ", by Daniel D. Miller, Copyright (c) 1995       "
#define THANKS_MESSAGE  "Thank you for using INTSUM version " cur_version " !!"

// #include <memcheck.h>

#define uchar  unsigned char
#define ulong  unsigned long

#define IFF    
#define THENN  ?
#define ELSSE  :

#define TAB    9

//********************************************************************
//  size of data buffers
extern const long BFR_SIZE ;

//  size of reverse read must be smaller than size of normal
//  read, so we are assured of finding current-line in our search.
extern const long REV_SIZE ;

extern const int LOOP_FOREVER ;

//********************************************************************
#define  IS_TRUE  != 0
//lint -e723
#define  IS_FALSE == 0

//********************  file-reading constants  ***********************
#define  DATA_OKAY      0
#define  FILE_OKAY      0
// define  OUT_OF_MEMORY  1  - duplicates errorcode from above
// define  BAD_FORMAT     2  - duplicates errorcode from above
#define  UNUSED_CODE    3
#define  OPEN_FAILED    4
#define  UNKNOWN_ERROR  5
#define  END_OF_FILE    6

//********************************************************************
//  Block reads usually under-shoot the actual buffer size            
//  by a certain amount, and that number of bytes is read             
//  into a separate buffer.  The reason for that is so I can          
//  search for end-of-line characters and tack them onto the          
//  end of the read buffer, ensuring that each buffer always          
//  contains complete lines.  This allows me to gain the speed        
//  advantage of block reads, without having to deal with             
//  partial lines in the program as a whole.                          
//                                                                    
//  The constant <UNDERSHOOT> is the number of bytes by which I       
//  under-read the block read, and read separately into the line      
//  buffer.  This value needs to be larger than the longest possible  
//  line in the input file.                                           
//********************************************************************
#define UNDERSHOOT   100

//********************************************************************
extern char rdtemp[UNDERSHOOT] ;

//********************************************************************
//  used by one-line message functions and partial screen-clear
//********************************************************************
extern char spaces[121] ;  //  120 spaces long

//********************************************************************
struct int_sum_line 
   {
   char  file ;            //  if ' ', use single list file, 
                           //  else use INTERRUP.<FILE>.
   // unsigned long  line ;   //  byte offset into interrupt file.
   char  foffset[8] ;      //  byte offset into interrupt file
   char  null_term ;       //  leave space to NULL-terminate the string
   char  data[81] ;        //  data to display onscreen.
   };

union sum_conv 
   {
   char  instr[sizeof(struct int_sum_line)] ;
   struct int_sum_line idx;
   };
extern const unsigned last_ref_char ;
extern const unsigned isl_lines ;

//*****************************************************************
//  reference-file data struct
//*****************************************************************
struct refs
   {
   sum_conv *bfr[2] ; //  forward and aft parsed buffers
   unsigned lines[2] ;     // number of lines of data in parsed buffers
   int cur_bfr ;      //  0 or 1
   unsigned offset ;  //  into current buffer
   //  file pointers used by fsetpos()
   long hdptr[2] ;
   long tlptr[2] ;  
   } ;
extern refs ref ;

//*****************************************************************
//  list-file data struct
//*****************************************************************
struct lines 
   {
   char instr[81] ;
   };

struct lists 
   {
   lines *bfr[2] ; //  forward and aft parsed buffers
   unsigned lines[2] ;     // number of lines of data in parsed buffers
   int cur_bfr ;      //  0 or 1
   unsigned offset ;  //  into current buffer
   //  file pointers used by fsetpos()
   long hdptr[2] ;
   long tlptr[2] ;  
   } ;
extern lists list ;

extern const unsigned list_lines ;

//  make this global so scrolling fcns can get to it.
extern FILE* lfile ;  

//*****************************************************************
//  string-search data struct
//*****************************************************************
struct searchs
   {
   sum_conv *bfr ;
   unsigned lines ;   // number of lines of data in parsed buffers
   unsigned offset ;  // line in current buffer
   //  file pointers used by fsetpos()
   long hdptr ;
   long tlptr ;  
   } ;
extern searchs search ;

//*****************************************************************
//  raw-data read buffer
//*****************************************************************
extern char* readptr ;

//*****************************************************************
//  misc data strings
//*****************************************************************
extern char tempstr[128] ;  //  scratchpad string
extern char oldstr[128] ;   //  used by reverse_search routines
extern char inipath[64] ;
extern char inidrive[4] ;
extern char ilpath[64] ;
extern char ildrive[4] ;

//*****************************************************************
extern "C" unsigned screen_rows ;
extern "C" unsigned screen_cols ;

extern uchar MAIN_TEXT ;
extern uchar SELECTED  ;
extern uchar LOGO      ;
extern uchar FILENAME  ;
extern uchar MESSAGE   ;
extern uchar INPUT     ;
extern uchar HELP_TEXT ;

//*****************************************************************
//  display structs
//*****************************************************************
extern const unsigned DATA_TOP ;
struct vidptr
   {
   unsigned currow ;    //  screen offset from DATA_TOP
   } ;
extern vidptr ivideo ;
      
extern unsigned window_rows ;  //  data lines, not counting header

extern FILE* index ;
//*****************************************************************
//  screen text
//*****************************************************************
extern char* logo ;
extern char* dividers ;
extern char* header ;
extern char* dividerd ;
extern char* list_header ;
extern char* list_dividerd ;

//*****************************************************************
ulong make_laddr(char* instr);
int  seek_next_line(FILE* infile);
unsigned fill_read_buffer(FILE* infile);
unsigned fill_search_buffer(FILE* infile);
void build_index(void);
void display_logo(void);
void display_list_file(void);
unsigned convert_lines(char* inbfr, unsigned rcount);

//  CONFIG.CPP
int read_ini_file(void);

//  REFFILE.CPP
void back_up_buffer1(void);
int search_ref_buffers(char *srchstr);
void search_ref_file(char *srchstr);
void fill_ref_buffers(fpos_t pos);
void scroll_page_up(void);
void scroll_page_down(void);
void display_ref_file(void);
unsigned fill_ref_bfr(unsigned bfr_flag);

//  LISTFILE.CPP
void process_list_file(int list_mode, char *save_file);
unsigned fill_list_bfr(unsigned bfr_flag);
void fill_ref_bfr_rev(void);
void fill_list_bfr_rev(void);
void scroll_list_down(void);
void scroll_list_up(void);

//  MSGS.CPP
void display_help(void);
unsigned message_read(char* msg_str, char* instr);
void message_show(char* msg_str);

//  STRSTRI.ASM
extern "C" int strstri(const char far* str1, const char far* str2);

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

