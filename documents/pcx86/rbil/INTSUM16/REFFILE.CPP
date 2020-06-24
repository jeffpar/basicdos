//********************************************************************
//  REFFILE.CPP - Handle RefFile display, searching, etc.             
//                                                                    
//  Copyright (c) 1996 Daniel D. Miller                               
//                                                                    
//  Last Update:  09-04-95 11:18pm                                    
//                                                                    
//  Compile with makefile                                             
//                                                                    
//********************************************************************

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dos.h>
#include "intsum.hpp"
#include "err_exit.hpp"
// #include <memcheck.h>

//*****************************************************************
void fill_ref_buffers(fpos_t pos)
   {
   //  adjust input-file position
   fsetpos(index, &pos) ;
   ref.hdptr[0] = pos ;

   // read data and fill ref_list buffer 0
   ref.lines[0] = fill_ref_bfr(0) ; //  fill forward buffer

   // read data and fill ref_list buffer 1
   ref.hdptr[1] = ref.tlptr[0] ;
   ref.lines[1] = fill_ref_bfr(1) ; //  fill aft buffer
   }

//*****************************************************************
//  first, search current ref buffer(s) starting at ref.offset.
//*****************************************************************
int search_ref_buffers(char *srchstr)
   {
   unsigned sline = ref.offset + (ivideo.currow - DATA_TOP) + 1 ;
   int srch_done ;
   //  first, search ref.bfr0 if active
   if (ref.cur_bfr == 0) 
      {
      if (sline > ref.lines[0]) 
         {
         sline -= ref.lines[0] ;
         }
      else 
         {
         srch_done = 0 ;
         while (!srch_done) 
            {
            //  If string is found, update buffers and move cursor
            if (strstri(ref.bfr[0][sline].idx.data, srchstr) == 0) 
               {
               ref.offset = sline ;
               //  I _think_ this is the correct position
               search.offset = sline ;
               ref.offset = sline ;

               ivideo.currow = DATA_TOP ;
               display_ref_file() ;
               return 0;
               }
            //  string is not yet found; move along in buffer0
            //  if at end of buffer, exit and try buffer 1.
            else if (++sline >= ref.lines[0]) 
               {
               srch_done = 1 ;
               sline = 0 ;
               }
            }  //  while not done searching
         }
      }

   //  then, search ref.bfr1 if active, and nothing found in 0
   if (ref.lines[1] > 0) 
      {
      srch_done = 0 ;
      while (!srch_done) 
         {
         //  If string is found, update buffers and move cursor
         if (strstri(ref.bfr[1][sline].idx.data, srchstr) == 0) 
            {
            search.offset = sline ;
            ref.cur_bfr = 1 ;
            ref.offset = sline ;
            ivideo.currow = DATA_TOP ;
            display_ref_file() ;
            return 0;
            }
         //  string is not yet found; move along in buffer1.
         //  if at end of buffer, exit and try other buffers.
         else if (++sline >= ref.lines[1]) 
            {
            srch_done = 1 ;
            sline = 0 ;
            }
         }  //  while not done searching
      }  //  if any lines are in buffer1, search it

   return -1 ;
   }

//*****************************************************************
//  current buffers have already been searched, with nothing found.
//  Now, search ref file starting at ref.tlptr[1].
//*****************************************************************
void search_ref_file(char *srchstr)
   {
   //  first, save current file pointer so it
   //  can be restored if no match is found.
   fpos_t oldpos ;
   fgetpos(index, &oldpos) ;

   //  position file pointer to current cursor position
   search.hdptr = ref.tlptr[1] ;
   fsetpos(index, &search.hdptr) ;
   //  move past it to current line (if possible)

   //  fill the readbfr from ref file
   unsigned rlines = fill_search_buffer(index) ;
   if (rlines == 0) 
      {
      message_show("Your search string was not found") ;
      return ;
      }

   unsigned sline = 0 ;
   int srch_done = 0 ;
   while (!srch_done) 
      {
      //  If string is found, update buffers and move cursor
      if (strstri(search.bfr[sline].idx.data, srchstr) == 0) 
         {
         // read real data from beginning of current block
         fsetpos(index, &search.hdptr) ;
         ref.hdptr[0] = search.hdptr ;
         fill_ref_buffers(search.hdptr) ;

         //  I _think_ this is the correct position
         search.offset = sline ;
         ref.offset = sline ;
         ref.cur_bfr = 0 ;

         ivideo.currow = DATA_TOP ;
         display_ref_file() ;
         srch_done = 1 ;
         }
      //  string is not yet found; move along in readbfr.
      //  if at end of buffer, read next buffer or fail.
      else if (++sline >= rlines) 
         {
         search.hdptr = search.tlptr ;
         rlines = fill_search_buffer(index) ;
         if (rlines == 0) 
            {
            //  restore input-file position
            fsetpos(index, &oldpos) ;
            srch_done = -1 ;
            message_show("Your search string was not found") ;
            }
         else 
            {
            sline = 0 ;
            }
         }
      }  //  while not done searching
   }

//*****************************************************************
void scroll_page_down(void)
   {
   //  if cursor is NOT at top, move cursor
   if (ivideo.currow > DATA_TOP) 
      {
      ivideo.currow-- ;
      }

   //  if cursor IS at top, try to move up in current buffer
   else if (ref.offset > 0)  //  scroll window down
      {
      ref.offset-- ;
      display_ref_file() ;
      }

   //  if current buffer is 1, just move back to buffer 0
   else if (ref.cur_bfr == 1)
      {
      ref.cur_bfr = 0 ;
      ref.offset = ref.lines[0] - 1 ;
      display_ref_file() ;
      }

   //  if current buffer = 0, see if we're at beginning of file.
   //  if so, do nothing; otherwise, try to read back in buffer,
   //  after copying buffer 0 to buffer 1.
   else if (ref.hdptr[0] > 0) 
      {
      //  copy buffer0 values to buffer1

      //  swap the buffer pointers
      sum_conv *b ;
      b          = ref.bfr[0] ;
      ref.bfr[0] = ref.bfr[1] ;
      ref.bfr[1] = b ;

      ref.lines[1] = ref.lines[0] ;
      ref.hdptr[1] = ref.hdptr[0] ;
      ref.tlptr[1] = ref.tlptr[0] ;
      //  current buffer remains 0.
      // ref.cur_bfr = 0 ;

      //  then compute and read new data into buffer0
      fill_ref_bfr_rev() ; //  fill forward buffer
      ref.offset-- ;
      display_ref_file() ;
      }
   }

//*****************************************************************
void scroll_page_up(void)
   {
   // end_line is line number for NEXT line
   unsigned end_line = ref.offset + window_rows ; //  base-0

   //  if still onscreen, just move cursor
   if (ivideo.currow+1 < screen_rows) 
      {
      ivideo.currow++ ;
      }

   //  end of screen...
   //  see if there's still room in buffer to move cursor
   else if (end_line < ref.lines[ref.cur_bfr])
         //   ^base-0        ^base-1     
      {
      ref.offset++ ;
      display_ref_file() ;
      }

   //  we are at end of buffer

   //@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
   //                      BUFFER 0                             
   //@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
   else if (ref.cur_bfr == 0) 
   //  If we're in buffer0, we should be able to slop over
   //  into buffer1, if there's any data in it.
      {
      //  if we were previously in buffer0, but now (after     
      //  adding one line) we don't fit in buffer0+buffer1,    
      //  there were less than (screen_size) lines in buffer1, 
      //  which means we're at end of file (otherwise, we      
      //  would have read roughly 32Kbytes).                   
      //                                                       
      //  NOTE: we do not currently handle scrolling           
      //        across multiple files.                         
      //                                                       
      if (end_line >= (ref.lines[0] + ref.lines[1])) 
         {
         //  do nothing for now...
         //  Later, we'll add multiple-file support.
         }
      //  If there is room in the two combined files, see if
      //  moving to next line has thrown us COMPLETELY into buffer1.
      else if ((ref.offset+1) == ref.lines[0])
         {
         ref.offset = 0 ;
         ref.cur_bfr = 1 ;
         display_ref_file() ;
         }
      //  otherwise, we're overlapping two files, 
      //  the ref function supports internally.
      else
         {
         ref.offset++ ;
         display_ref_file() ;
         }
      }

   //@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
   //                      BUFFER 1                             
   //@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
   //  if NOT at end of buffer 1, update array offset and redraw
   else if (end_line < ref.lines[1]) 
      {
      ref.offset++ ;
      display_ref_file() ;
      }
   //  if we reach end of buffer 1, 
   //  copy buffer 1 to buffer 0 and see if
   //  there's more data to scroll into.
   else 
      {
      back_up_buffer1() ;
      if (ref.lines[1] > 0) 
         {
         ref.offset++ ;
         display_ref_file() ;
         }
      }
   }

//*****************************************************************
//  copy ref buffer 1 to ref buffer 0,
//  then refill ref buffer 1
//*****************************************************************
void back_up_buffer1(void)
   {
   //  swap the buffer pointers
   sum_conv *b  = ref.bfr[0] ;
   ref.bfr[0]   = ref.bfr[1] ;
   ref.bfr[1]   = b ;
   //  copy buffer1 data to buffer0 struct
   ref.lines[0] = ref.lines[1] ;
   ref.hdptr[0] = ref.hdptr[1] ;
   ref.tlptr[0] = ref.tlptr[1] ;
   ref.cur_bfr  = 0 ;
   ref.hdptr[1] = ref.tlptr[0] ;

   //  read new data into buffer1
   ref.lines[1] = fill_ref_bfr(1) ;
   }

//*****************************************************************
void display_ref_file(void)
   {
   unsigned new_top, j, buffer_left = ref.lines[ref.cur_bfr] - ref.offset ;
           //     ^base-1            ^base-1             ^base-0

   //  if current buffer fits entirely onscreen
   if (window_rows <= buffer_left) 
      {
      for (j=0; j<window_rows; j++) 
         {
         dprints(0, DATA_TOP+j, MAIN_TEXT, 
            ref.bfr[ref.cur_bfr][ref.offset+j].idx.data) ;
         }
      }

   //  if we're currently using buffer 0, just lop over into bfr 1.
   //  Fill any unused lines with blank lines.
   else if (ref.cur_bfr == 0)
      {
      if (window_rows > (buffer_left + ref.lines[1])) 
         //  ^base1        ^base1         ^base1
         {
         //  draw remainder of buffer0
         for (j=0; j<buffer_left; j++) 
            {
            dprints(0, DATA_TOP+j, MAIN_TEXT, 
               ref.bfr[0][ref.offset+j].idx.data) ;
            }
         //  draw all of buffer1
         new_top = DATA_TOP + buffer_left ;
         for (j=0; j<ref.lines[1]; j++) 
            {
            dprints(0, new_top++, MAIN_TEXT, ref.bfr[1][j].idx.data) ;
            }
         //  draw blank lines
         spaces[80] = 0 ;
         while (new_top < screen_rows) 
            {
            dprints(0, new_top++, MAIN_TEXT, spaces) ;
            }
         spaces[80] = ' ' ;
         }
      else 
         {
         for (j=0; j<buffer_left; j++) 
            {
            dprints(0, DATA_TOP+j, MAIN_TEXT, 
               ref.bfr[0][ref.offset+j].idx.data) ;
            }
         for (j=0; j<(window_rows-buffer_left); j++) 
            {
            dprints(0, DATA_TOP+buffer_left+j, MAIN_TEXT, 
               ref.bfr[1][j].idx.data) ;
            }
         }
      }

   //  we're at end of buffer 1
   else 
      {
      //  copy bfr1 to bfr0, then refill bfr1
      back_up_buffer1() ;

      //  recursive call to this routine
      display_ref_file() ;
      }
   }

//*****************************************************************
//  parse lines from input file.
//*****************************************************************
unsigned fill_ref_bfr(unsigned bfr_flag)
   {
   int done = 0 ;
   //lint -e740
   unsigned offseti = FP_OFF(readptr) ;   // init value for byte tfr counter
   unsigned offsetf ;
   unsigned count = 0, j ;

   //  fill the readbfr from ref file
   unsigned rlines = fill_read_buffer(index) ;
   if (rlines == 0) 
      return 0;

   //  now, translate the read buffer into the ref-list buffer
   unsigned lcount = isl_lines ;
   char *sptr = readptr ;
   while (!done) 
      {
      unsigned slen = strlen(sptr) ;
      strcpy(ref.bfr[bfr_flag][count].instr, sptr) ;

      //  pad short lines with spaces
      if (slen < sizeof(sum_conv)) 
         {
         for (j=slen; j<last_ref_char; j++) 
            ref.bfr[bfr_flag][count].instr[j] = ' ' ;
         //  now, NULL-terminate the line
         ref.bfr[bfr_flag][count].instr[last_ref_char] = 0 ;
         }

      //  point to next string in buffer
      sptr += slen ;
      while (*sptr == 0)  sptr++ ;   //  seek beginning of next line

      count++ ;
      //@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
      //  If this terminates on lcount, rather than rlines, 
      //  the input buffer will have to be adjusted
      //@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
      if (--lcount == 0  ||  count == rlines) 
         {
         done = 1 ;
         //  set tail-pointer variable in current ref struct
         offsetf = FP_OFF(sptr) ;   //lint !e740
         ref.tlptr[bfr_flag] = ref.hdptr[bfr_flag]
                                 + (offsetf - offseti) ;
         //  adjust input-file position
         fpos_t pos = ref.tlptr[bfr_flag] ;
         fsetpos(index, &pos) ;
         }
      }

   return count;
   }

//*****************************************************************
//  parse lines from input file, after reading 
//  BACK from current file position.
//  This is always performed on buffer0.
//  It is assumed that buffer0 struct has already
//  been copied to buffer 1.
//*****************************************************************
void fill_ref_bfr_rev(void)
   {
   //  make a copy of current line before overwriting it,
   //  so we can find it again afterwards
   strcpy(oldstr, ref.bfr[1][ref.offset].instr) ;
   if (strlen(oldstr) == 0) 
      error_exit(BAD_FORMAT, NULL) ;

   //  figure out how far to back up the read pointer
   fpos_t pos = IFF   (ref.hdptr[0] > REV_SIZE) 
                THENN (ref.hdptr[0] - REV_SIZE)
                ELSSE 0 ;

   //  adjust input-file position and fill ref buffers
   fsetpos(index, &pos) ;
   int icount = seek_next_line(index) ;
   if (icount < 0)
      error_exit(BAD_SEARCH, NULL) ;
   pos += icount ;
   fill_ref_buffers(pos) ;

   //  now that new buffers have been read, 
   //  seek to the current line and update ref.offset
   unsigned count = 0 ;
   int done = 0 ;
   while (!done) 
      {
      if (strncmp(oldstr, ref.bfr[0][count].instr, 9) == 0) 
         {
         ref.offset = count ;
         done = 1 ;
         }
      else if (++count >= ref.lines[0])
         error_exit(BAD_SEARCH, NULL) ; 
      }
   }


