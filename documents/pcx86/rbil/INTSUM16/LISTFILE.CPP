//********************************************************************
//  LISTFILE.CPP - Handle ListFile display, searching, etc.           
//                                                                    
//  Copyright (c) 1996 Daniel D. Miller                               
//                                                                    
//  Last Update:  09-04-95 11:17pm                                    
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
#include "keycodes.h"
// #include <memcheck.h>

static char srchstr[81] ;

//*****************************************************************
static void fill_list_buffers(fpos_t pos);
static int  search_list_buffers(void);
static void search_list_file(void);
static void back_up_list1(void);

//*****************************************************************
void process_list_file(int list_mode, char *save_file)
   {
   char sfile[128], sname[13] ;
   char lstr[sizeof(sum_conv)+1] ;
   unsigned j, ref_bfr ;

   int_sum_line *iptr = (int_sum_line *) lstr ;

   dprints(0, 2, LOGO, list_header) ;
   dprints(0, 3, LOGO, list_dividerd) ;

   //  initialize list-file variables which are not
   //  otherwise later set up.
   list.offset = 0 ; 
   list.cur_bfr = 0 ;
   list.hdptr[0] = 0L ;

   //  figure out which line in ref file was selected
   ref_bfr = (unsigned) ref.cur_bfr ;
   unsigned currow = ref.offset + ivideo.currow - DATA_TOP ;
   if (currow > (ref.lines[0] + ref.lines[1])) 
      return ;
   if (ref.cur_bfr == 0  &&  currow > ref.lines[0]) 
      {
      ref_bfr = 1 ;
      currow -= ref.lines[0] ;
      }
   else if (ref.cur_bfr == 1  &&  currow > ref.lines[1]) 
      return ;

   //  read appropriate data into list-file struct.
   strcpy(lstr, ref.bfr[ref_bfr][currow].instr) ;

   if (iptr->file == ' ') 
      {
      _makepath(sfile, ildrive, ilpath, "interrup", "lst") ;
      strcpy(sname,"interrup.lst") ;
      }
   else 
      {
      char c2s[5] ;
      c2s[0] = iptr->file ;
      c2s[1] = NULL ;
      _makepath(sfile, ildrive, ilpath, "interrup", c2s) ;
      _makepath(sname, NULL, NULL, "interrup", c2s) ;
      }

   //  determine file offset
   iptr->null_term = 0 ;
   fpos_t loffset = strtol(iptr->foffset, NULL, 16) ;

   //  open the file
   lfile = fopen(sfile, "rb") ;
   if (lfile == NULL) 
      error_exit(NO_READ_FILE, sfile) ;

   fill_list_buffers(loffset) ;  //  fill the list buffers

   //  now, determine whether this is a "print topic" call 
   //  or a normal "display" call
   if (list_mode == 1) 
      {
      //  open the output file
      FILE* outfile = fopen(save_file, "wt") ;
      if (outfile == NULL) 
         {
         strupr(save_file) ;
         sprintf(tempstr, "cannot open %s", save_file) ;
         message_show(tempstr) ;
         fclose(lfile) ;
         dprints(0, 2, LOGO, header) ;
         dprints(0, 3, LOGO, dividerd) ;
         return ;
         }

      //  write the data into it
      ref_bfr = 0 ;  //  overloading this variable
      j=0 ;
      do {
         fprintf(outfile, "%s\n", list.bfr[ref_bfr][j].instr) ;
         if (++j > list.lines[ref_bfr]) 
            {
            j = 0 ;
            if (++ref_bfr == 2) 
               {
               fill_list_buffers(list.tlptr[1]) ;  //  refill the list buffers
               ref_bfr = 0 ;
               }
            }
         }
      while (strncmp(list.bfr[ref_bfr][j].instr, "--------", 8) != 0) ;

      //  close files and exit
      fclose(outfile) ;
      fclose(lfile) ;
      dprints(0, 2, LOGO, header) ;
      dprints(0, 3, LOGO, dividerd) ;
      return ;
      }

   //  display current filename on screen
   dprints(1, 2, FILENAME, sname) ;

   //  display the first buffer of data
   ivideo.currow = DATA_TOP ;
   display_list_file() ;

   //  list-file keyboard handler
   srchstr[0] = 0 ;  //  reset the search string
   unsigned rtemp ;
   int count ;
   int done = 0 ;
   while (!done) 
      {
      mark_cursor_line(ivideo.currow, SELECTED) ;
      unsigned indata = get_key() ;
      mark_cursor_line(ivideo.currow, MAIN_TEXT) ;
      switch (indata) 
         {
         case Key_UP:
            scroll_list_down() ;
            break;

         case Key_PGUP:
            rtemp = ivideo.currow ;
            ivideo.currow = DATA_TOP ;
            for (j=0; j<window_rows; j++) 
               scroll_list_down() ;
            ivideo.currow = rtemp ;
            break;

         case Key_DOWN:
            scroll_list_up() ;
            break;

         case Key_PGDN:
            rtemp = ivideo.currow ;
            ivideo.currow = screen_rows - 1 ;
            for (j=0; j<window_rows; j++) 
               scroll_list_up() ;
            ivideo.currow = rtemp ;
            break;

         case Key_HOME:
            loffset = 0 ;
            fill_list_buffers(loffset) ;
            list.offset = 0 ;
            list.cur_bfr = 0 ;
            ivideo.currow = DATA_TOP ;
            display_list_file() ;
            break;

         case Key_END:
            //  seek end of file
            fseek(lfile, 0L, SEEK_END) ;
            fgetpos(lfile, &loffset) ;
            loffset -= REV_SIZE ;

            //  adjust input-file position, then
            //  read one line and re-position file pointer to full line
            fsetpos(lfile, &loffset) ;
            count = seek_next_line(lfile) ;
            if (count < 0) 
               error_exit(BAD_SEARCH, NULL) ;
            loffset += count ;
            fill_list_buffers(loffset) ;

            //  now, figure out which line is top of (end of screen)
            if (list.lines[1] < window_rows) 
               {
               list.cur_bfr = 0 ;
               list.offset =  list.lines[0] + list.lines[1] - window_rows ;
               }
            else 
               {
               list.cur_bfr = 1 ;
               list.offset = list.lines[1] - window_rows ;
               }

            ivideo.currow = DATA_TOP ;
            display_list_file() ;
            break;

         case Key_F1:
         case Key_h:
         case Key_H: //  display help screen
            display_help() ;
            display_logo() ;
            dprints(0, 2, LOGO, list_header) ;
            display_list_file() ;
            break;

         case Key_F2:
         case Key_s:
         case Key_S: //  search for string
            if (message_read("Enter string to search for: ", srchstr) == 0)
               {
               if (search_list_buffers() != 0) 
                   search_list_file() ;
               }
            //  redraw current filename on screen
            dprints(0, 2, LOGO, list_header) ;
            dprints(1, 2, FILENAME, sname) ;
            break;

         case Key_F3:
         case Key_r:
         case Key_R: //  repeat last string search
            if (strlen(srchstr) == 0) 
               message_show("There is no current search string") ;
            else if (search_list_buffers() != 0) 
                search_list_file() ;
            //  redraw current filename on screen
            dprints(0, 2, LOGO, list_header) ;
            dprints(1, 2, FILENAME, sname) ;
            break;

         case Key_ESC:
            fclose(lfile) ;
            dprints(0, 2, LOGO, header) ;
            dprints(0, 3, LOGO, dividerd) ;
            done = 1 ;
            break;

         default:
            break;
         }  //  keyboard switch
      }  //  while not done
   }

//*****************************************************************
void fill_list_buffers(fpos_t pos)
   {
   //  adjust input-file position
   fsetpos(lfile, &pos) ;
   list.hdptr[0] = pos ;

   // read data and fill list_list buffer 0
   list.lines[0] = fill_list_bfr(0) ; //  fill forward buffer

   // read data and fill list_list buffer 1
   list.hdptr[1] = list.tlptr[0] ;
   list.lines[1] = fill_list_bfr(1) ; //  fill aft buffer
   }

//*****************************************************************
//  first, search current list buffer(s) starting at list.offset.
//*****************************************************************
int search_list_buffers(void)
   {
   unsigned sline = list.offset + (ivideo.currow - DATA_TOP) + 1 ;
   int srch_done ;
   //  first, search list.bfr0 if active
   if (list.cur_bfr == 0) 
      {
      srch_done = 0 ;
      if (sline <= list.lines[0]) 
         {
         while (!srch_done) 
            {
            //  If string is found, update buffers and move cursor
            if (strstri(list.bfr[0][sline].instr, srchstr) == 0) 
               {
               list.offset = sline ;
               //  I _think_ this is the correct position
               search.offset = sline ;
               list.offset = sline ;

               ivideo.currow = DATA_TOP ;
               display_list_file() ;
               return 0;
               }
            //  string is not yet found; move along in buffer0
            //  if at end of buffer, exit and try buffer 1.
            else if (++sline >= list.lines[0]) 
               {
               srch_done = 1 ;
               sline = 0 ;
               }
            }  //  while not done searching
         }  //  if first search line actually IS in bfr0
      //  if search line lapses into bfr1, move there
      else 
         {
         sline -= list.lines[0] ;
         }
      }

   //  then, search list.bfr1 if active, and nothing found in 0
   if (list.lines[1] > 0) 
      {
      srch_done = 0 ;
      while (!srch_done) 
         {
         //  If string is found, update buffers and move cursor
         if (strstri(list.bfr[1][sline].instr, srchstr) == 0) 
            {
            search.offset = sline ;
            list.cur_bfr = 1 ;
            list.offset = sline ;
            ivideo.currow = DATA_TOP ;
            display_list_file() ;
            return 0;
            }
         //  string is not yet found; move along in buffer1.
         //  if at end of buffer, exit and try other buffers.
         else if (++sline >= list.lines[1]) 
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
//  Now, search list file starting at list.tlptr[1].
//*****************************************************************
void search_list_file(void)
   {
   //  first, save current file pointer so it
   //  can be restored if no match is found.
   fpos_t oldpos ;
   fgetpos(lfile, &oldpos) ;

   //  position file pointer to current cursor position
   search.hdptr = list.tlptr[1] ;
   fsetpos(lfile, &search.hdptr) ;
   //  move past it to current line (if possible)

   //  fill the readbfr from list file
   unsigned rlines = fill_search_buffer(lfile) ;
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
      if (strstri(search.bfr[sline].instr, srchstr) == 0) 
         {
         // read real data from beginning of current block
         fill_list_buffers(search.hdptr) ;

         //  I _think_ this is the correct position
         search.offset = sline ;
         list.offset = sline ;
         list.cur_bfr = 0 ;

         ivideo.currow = DATA_TOP ;
         display_list_file() ;
         srch_done = 1 ;
         }
      //  string is not yet found; move along in readbfr.
      //  if at end of buffer, read next buffer or fail.
      else if (++sline >= rlines) 
         {
         search.hdptr = search.tlptr ;
         rlines = fill_search_buffer(lfile) ;
         if (rlines == 0) 
            {
            //  restore input-file position
            fsetpos(lfile, &oldpos) ;
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
void scroll_list_down(void)
   {
   //  if cursor is NOT at top, move cursor
   if (ivideo.currow > DATA_TOP) 
      {
      ivideo.currow-- ;
      }
   //  if cursor IS at top, try to move up in current buffer
   else if (list.offset > 0)  //  scroll window down
      {
      list.offset-- ;
      display_list_file() ;
      }
   //  if current buffer is 1, just move back to buffer 0
   else if (list.cur_bfr == 1)
      {
      list.cur_bfr = 0 ;
      list.offset = list.lines[0] - 1 ;
      display_list_file() ;
      }
   //  if current buffer = 0, see if we're at beginning of file.
   //  if so, do nothing; otherwise, try to read back in buffer,
   //  after copying buffer 0 to buffer 1.
   else if (list.hdptr[0] > 0) 
      {
      //  copy buffer0 values to buffer1

      //  swap the buffer pointers
      lines *b    = list.bfr[0] ;
      list.bfr[0] = list.bfr[1] ;
      list.bfr[1] = b ;

      list.lines[1] = list.lines[0] ;
      list.hdptr[1] = list.hdptr[0] ;
      list.tlptr[1] = list.tlptr[0] ;
      //  current buffer remains 0.
      // list.cur_bfr = 0 ;

      //  then compute and read new data into buffer0
      fill_list_bfr_rev() ; //  fill forward buffer
      if (list.offset > 0) 
         list.offset-- ;
      display_list_file() ;
      }
   }

//*****************************************************************
void scroll_list_up(void)
   {
   // end_line is line number for NEXT line
   unsigned end_line = list.offset + window_rows ; //  base-0

   //  if still onscreen, just move cursor
   if (ivideo.currow+1 < screen_rows) 
      {
      ivideo.currow++ ;
      }

   //  end of screen...
   //  see if there's still room in buffer to move cursor
   else if (end_line < list.lines[list.cur_bfr])
         //   ^base-0        ^base-1     
      {
      list.offset++ ;
      display_list_file() ;
      }

   //  we are at end of buffer

   //@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
   //                      BUFFER 0                             
   //@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
   else if (list.cur_bfr == 0) 
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
      if (end_line >= (list.lines[0] + list.lines[1])) 
         {
         //  do nothing for now...
         //  Later, we'll add multiple-file support.
         }
      //  If there is room in the two combined files, see if
      //  moving to next line has thrown us COMPLETELY into buffer1.
      else if ((list.offset+1) == list.lines[0])
         {
         list.offset = 0 ;
         list.cur_bfr = 1 ;
         display_list_file() ;
         }
      //  otherwise, we're overlapping two files, 
      //  which the list function supports internally.
      else
         {
         list.offset++ ;
         display_list_file() ;
         }
      }

   //@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
   //                      BUFFER 1                             
   //@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
   //  if NOT at end of buffer 1, update array offset and redraw
   else if (end_line < list.lines[1]) 
         //  ^base0      ^base1     
      {
      list.offset++ ;
      display_list_file() ;
      }
   //  if we reach end of buffer 1, 
   //  copy buffer 1 to buffer 0 and see if
   //  there's more data to scroll into.
   else 
      {
      back_up_list1() ;
      if (list.lines[1] > 0) 
         {
         list.offset++ ;
         display_list_file() ;
         }
      }
   }

//*****************************************************************
void back_up_list1(void)
   {
   //  swap the buffer pointers
   lines *b      = list.bfr[0] ;
   list.bfr[0]   = list.bfr[1] ;
   list.bfr[1]   = b ;
   //  copy buffer1 data to buffer0 struct
   list.lines[0] = list.lines[1] ;
   list.hdptr[0] = list.hdptr[1] ;
   list.tlptr[0] = list.tlptr[1] ;
   list.cur_bfr  = 0 ;
   list.hdptr[1] = list.tlptr[0] ;

   //  read new data into buffer1
   list.lines[1] = fill_list_bfr(1) ;
   }

//*****************************************************************
void display_list_file(void)
   {
   //  buffer_left is 1-based
   unsigned j, buffer_left = list.lines[list.cur_bfr] - list.offset ;
           //     ^base-1            ^base-1             ^base-0

   //  if current buffer fits entirely onscreen
   if (window_rows <= buffer_left) 
      {
      for (j=0; j<window_rows; j++) 
         {
         dprints(0, DATA_TOP+j, MAIN_TEXT, 
            list.bfr[list.cur_bfr][list.offset+j].instr) ;
         }
      }
   //  if we're currently using buffer 0, just lop over into bfr 1
   //  Fill any unused lines with blank lines.
   else if (list.cur_bfr == 0)
      {
      if (window_rows > (buffer_left + list.lines[1])) 
         //  ^base1        ^base1         ^base1
         {
         //  draw remainder of buffer0
         for (j=0; j<buffer_left; j++) 
            {
            dprints(0, DATA_TOP+j, MAIN_TEXT, 
               list.bfr[0][list.offset+j].instr) ;
            }
         //  draw all of buffer1
         unsigned new_top = DATA_TOP + buffer_left ;
         for (j=0; j<list.lines[1]; j++) 
            {
            dprints(0, new_top++, MAIN_TEXT, list.bfr[1][j].instr) ;
            }
         //  draw blank lines
         spaces[80] = 0 ;
         //for (j=new_top; j<screen_rows; j++) 
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
               list.bfr[0][list.offset+j].instr) ;
            }
         for (j=0; j<(window_rows-buffer_left); j++) 
            {
            dprints(0, DATA_TOP+buffer_left+j, MAIN_TEXT, 
                    list.bfr[1][j].instr) ;
            }
         }
      }
   //  we're at end of buffer 1; are we at EOF??
   else 
      {
      //  copy buffer1 to buffer0,
      //  then refill buffer 1.
      back_up_list1() ;

      //  recursively call this display routine
      display_list_file() ;
      }
   }

//*****************************************************************
//  parse lines from input file.
//*****************************************************************
const unsigned TAB_SIZE = 8 ;

unsigned fill_list_bfr(unsigned bfr_flag)
   {
   int done = 0 ;
   //lint -e740
   unsigned offseti = FP_OFF(readptr) ;   // init value for byte tfr counter
   unsigned offsetf ;
   unsigned count = 0, j ;

   //  fill the readbfr from list file
   unsigned rlines = fill_read_buffer(lfile) ;
   if (rlines == 0) 
      return 0;

   //  now, translate the read buffer into the list-list buffer
   unsigned lcount = 0 ;   // output_buffer counter
   char *sptr = readptr ;
   while (!done) 
      {
      unsigned slen = strlen(sptr) ;

      if (slen == 0) //  insert a blank line
         {
         spaces[80] = 0 ;
         strcpy(list.bfr[bfr_flag][lcount].instr, spaces) ;
         spaces[80] = ' ' ;
         }

      //  copy data to list buffer.  strcpy() won't do because
      //  TABs have to be converted from the input files.
      //strcpy(list.bfr[bfr_flag][lcount].instr, sptr) ;
      else 
         {
         char* cptr = sptr ;
         j = 0 ;
         while (j < 80  &&  *cptr != 0) 
            {
            switch (*cptr) 
               {
               case TAB:
                  do {
                     if (j < 80) 
                        {
                        list.bfr[bfr_flag][lcount].instr[j] = ' ' ;
                        }
                     j++ ;
                     }
                  while ((j % TAB_SIZE) != 0);
                  cptr++ ; //  strip the TAB char from input
                  break;

               default:
                  list.bfr[bfr_flag][lcount].instr[j++] = *cptr++ ;
                  break;
               }  //  switch (input char)
            }

         //  if input line is longer than 80 chars, skim ahead to EOL
         if (j == 80) 
            {
            while (*cptr != 0)  cptr++ ;
            }
         else
            {
            //  pad short lines with spaces
            while (j < 80) 
               {
               list.bfr[bfr_flag][lcount].instr[j++] = ' ' ;
               }
            }
         list.bfr[bfr_flag][lcount].instr[80] = 0 ;  //  NULL-term the line

         //  point to next string in buffer
         sptr += slen ;
         }  //  copy line to list buffer, expanding TABs

      //  skip NULLs, which were formerly CR/LF
      //  Skipping ALL NULLs is not appropriate, as this
      //  effectively deletes blank lines.
      //  We should skip at most 2 NULLs, then add all
      //  further NULL pairs as blank lines.
      if (*sptr == NULL) sptr++ ;   //  skip CR
      if (*sptr == NULL) sptr++ ;   //  skip LF
      count++ ;
      lcount++ ;

      //@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
      //  Determine if we are at end of input data (count),
      //  or if output buffer is full (lcount)
      //@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
      if (lcount == list_lines  ||  count == rlines) 
         {
         done = 1 ;
         //  set tail-pointer variable in current list struct
         offsetf = FP_OFF(sptr) ;   //lint !e740
         list.tlptr[bfr_flag] = list.hdptr[bfr_flag] + (offsetf - offseti) ;
         //  adjust input-file position
         fpos_t pos = list.tlptr[bfr_flag] ;
         fsetpos(lfile, &pos) ;
         }
      }  //  while not done filling input buffer

   return count;
   }

//*****************************************************************
void fill_list_bfr_rev(void)
   {
   unsigned count ;
   int done, icount ;

   //  make a copy of current line before overwriting it,
   //  so we can find it again afterwards
   strcpy(oldstr, list.bfr[1][list.offset].instr) ;
   if (strlen(oldstr) == 0) 
      error_exit(BAD_FORMAT, NULL) ;

   //  figure out how far to back up the read pointer
   fpos_t pos = IFF   (list.hdptr[0] > REV_SIZE) 
                THENN (list.hdptr[0] - REV_SIZE)
                ELSSE 0 ;

   //  now read one line and re-position file pointer to full line
   //  (if we're at beginning of file, don't bother)
   if (pos > 0) 
      {
      fsetpos(lfile, &pos) ;
      icount = seek_next_line(lfile) ;
      if (icount < 0) 
         error_exit(BAD_SEARCH, NULL) ;
      pos += icount ;
      }
   fill_list_buffers(pos) ;

   //  now that new buffers have been read, 
   //  seek to the current line and update list.offset
   count = 0 ;
   done = 0 ;
   while (!done) 
      {
      if (strcmp(oldstr, list.bfr[0][count].instr) == 0) 
         {
         list.offset = count ;
         done = 1 ;
         }
      else if (++count >= list.lines[0])
         error_exit(BAD_SEARCH, NULL) ; 
      }
   }

