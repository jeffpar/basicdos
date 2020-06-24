//********************************************************************
//  INTSUM.CPP - Display/search program for Ralf Brown's              
//               Interrupt List.                                      
//                                                                    
//  Copyright (c) 1996 Daniel D. Miller                               
//                                                                    
//  Last Update:  09-08-95 08:42pm                                    
//                                                                    
//  Compile with makefile                                             
//                                                                    
//********************************************************************

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dos.h>
#include <graph.h>
#include "intsum.hpp"
#include "err_exit.hpp"
#include "keycodes.h"
// #include <memcheck.h>

//*****************************************************************
main(int argc, char** argv)
   {
   int done, count ;
   unsigned j ;
   uchar char_attr ;

   //  make sure at least DOS 3.0 is running
   if (_osmajor < 3)
      error_exit(OLD_DOS_VERSION, NULL) ;

   //  get path for executable file
   _splitpath(argv[0], inidrive, inipath, NULL, NULL) ;

   //  calculate video parameters
   char_attr = get_char_attr() ;
   get_vsize() ;
   window_rows = screen_rows - DATA_TOP ; //  base-1
   select_video_seg(0) ;   // auto-detect video segment

   //  initialize the path for IntList files, 
   //  before reading INI file.
   strcpy(ildrive, inidrive) ;
   strcpy(ilpath , inipath) ;

   //  search for/parse INI file
   read_ini_file() ;

   //  allocate raw-data read buffer
   readptr = new char[(unsigned) BFR_SIZE] ;
   if (readptr == NULL) 
      error_exit(OUT_OF_MEMORY, NULL) ;

   //  allocate ref-file buffers
   ref.bfr[0] = new sum_conv[isl_lines] ;
   if (ref.bfr[0] == NULL) 
      error_exit(OUT_OF_MEMORY, NULL) ;
   ref.bfr[1] = new sum_conv[isl_lines] ;
   if (ref.bfr[1] == NULL) 
      error_exit(OUT_OF_MEMORY, NULL) ;

   //  allocate ref-search buffer
   search.bfr = new sum_conv[isl_lines] ;
   if (search.bfr == NULL) 
      error_exit(OUT_OF_MEMORY, NULL) ;

   //  allocate list-file buffers
   list.bfr[0] = new lines[list_lines] ;
   if (list.bfr[0] == NULL) 
      error_exit(OUT_OF_MEMORY, NULL) ;
   list.bfr[1] = new lines[list_lines] ;
   if (list.bfr[1] == NULL) 
      error_exit(OUT_OF_MEMORY, NULL) ;

   //  search for interrup.idx
   //  Build it if not present
   //  
   //  NOTE: if files are opened in TEXT mode,
   //        EOLs get translated from CRLF in file to \n in buffer,
   //        and "bytes read" is not what was asked for.
   //        This program uses BINARY to solve some of these problems.
   _makepath(tempstr, ildrive, ilpath, "interrup", "idx") ;
   index = fopen(tempstr, "rb") ;
   if (index == NULL) 
      {
      build_index() ;
      _makepath(tempstr, ildrive, ilpath, "interrup", "idx") ;
      index = fopen(tempstr, "rb") ;
      if (index == NULL) 
         error_exit(NO_READ_FILE, "interrup.idx") ;
      }
   //  leave ref file open

   //  initialize variables and read first ref buffer
   ref.cur_bfr  = 0 ;
   ref.offset   = 0 ;
   fpos_t pos = 0 ;
   fill_ref_buffers(pos) ;
   
   //****************************************
   //  hold off building display until 
   //  setup operations are successful.
   //****************************************

   //  hide the cursor
   hide_cursor() ;

   //  display our logo
   clear_display(MAIN_TEXT) ;
   display_logo() ;

   // display the first window
   display_ref_file() ;

   //  main keyboard handler
   char srchstr[81] ;
   srchstr[0] = 0 ;  // reset initial search string
   unsigned rtemp ;
   done = 0 ;
   while (!done) 
      {
      mark_cursor_line(ivideo.currow, SELECTED) ;
      unsigned indata = get_key() ;
      mark_cursor_line(ivideo.currow, MAIN_TEXT) ;
      switch (indata) 
         {
         case Key_ENTER:   //  seek info on current entry
            rtemp = ivideo.currow ;
            process_list_file(0, NULL) ;
            ivideo.currow = rtemp ;
            display_ref_file() ;
            break;

         case Key_UP:
            scroll_page_down() ;
            break;

         case Key_HOME:
            //  position cursor at beginning of file
            pos = 0 ;
            fill_ref_buffers(pos) ;
            ref.offset = 0 ;
            ref.cur_bfr = 0 ;
            ivideo.currow = DATA_TOP ;
            display_ref_file() ;
            break;

         case Key_END:
            //  seek end of file
            fseek(index, 0L, SEEK_END) ;
            fgetpos(index, &pos) ;
            pos -= REV_SIZE ;

            //  adjust input-file position
            fsetpos(index, &pos) ;
            ref.hdptr[0] = pos ;

            //  now read one line and re-position file pointer to full line
            count = seek_next_line(index) ;
            if (count < 0) 
               error_exit(BAD_SEARCH, NULL) ;
            pos += count ;
            fill_ref_buffers(pos) ;

            //  now, figure out which line is top of (end of screen)
            if (ref.lines[1] < window_rows) 
               {
               ref.cur_bfr = 0 ;
               ref.offset =  ref.lines[0] + ref.lines[1] - window_rows ;
               }
            else 
               {
               ref.cur_bfr = 1 ;
               ref.offset = ref.lines[1] - window_rows ;
               }

            ivideo.currow = DATA_TOP ;
            display_ref_file() ;
            break;

         case Key_PGUP:
            rtemp = ivideo.currow ;
            ivideo.currow = DATA_TOP ;
            for (j=0; j<window_rows; j++) 
               scroll_page_down() ;
            ivideo.currow = rtemp ;
            break;

         case Key_DOWN:
            scroll_page_up() ;
            break;

         case Key_PGDN:
            rtemp = ivideo.currow ;
            ivideo.currow = screen_rows - 1 ;
            for (j=0; j<window_rows; j++) 
               scroll_page_up() ;
            ivideo.currow = rtemp ;
            break;

         case Key_F1:
         case Key_h:
         case Key_H: //  display help screen
            display_help() ;
            display_logo() ;
            display_ref_file() ;
            break;

         case Key_F2:
         case Key_s:
         case Key_S: //  search for string
            if (message_read("Enter string to search for: ", srchstr) == 0)
               {
               if (search_ref_buffers(srchstr) != 0) 
                   search_ref_file(srchstr) ;
               }
            break;

         case Key_F3:
         case Key_r:
         case Key_R: //  repeat last string search
            if (strlen(srchstr) == 0) 
               message_show("There is no current search string") ;
            else if (search_ref_buffers(srchstr) != 0) 
                search_ref_file(srchstr) ;
            break;

         case Key_F4:
         case Key_t:
         case Key_T: //  save current topic
            char sfile[81] ;  //  local storage for filename
            if (message_read("Enter filename to save to: ", sfile) == 0  &&
                strlen(sfile) > 0)
               {
               rtemp = ivideo.currow ;
               process_list_file(1, sfile) ;
               ivideo.currow = rtemp ;
               display_ref_file() ;
               }
            break;

         case Key_ESC:
            //  delete buffers explicitly, so the allocations
            //  aren't shown by memory checkers.
            delete readptr ;
            delete ref.bfr[0] ;
            delete ref.bfr[1] ;
            delete search.bfr ;
            delete list.bfr[0] ;
            delete list.bfr[1] ;
            done = 1 ;
            break;

         default:
            break;
         }
      }

   clear_display(char_attr) ;
   home_cursor() ;
   puts(THANKS_MESSAGE) ;
   puts("        Copyright (c) 1995 Dan Miller") ;
   puts("             derelict@netcom.com") ;
   return 0;
   }

//*****************************************************************
//  read <UNDERSHOOT> bytes from (infile) into global (rdtemp),    
//  then scan to beginning of next line and return number          
//  of bytes to that next line.                                    
//*****************************************************************
int seek_next_line(FILE* infile)
   {
   int count = 0 ;
   fread(rdtemp, 1, UNDERSHOOT, infile) ;
   int done = 0 ;
   while (!done) 
      {
      if (rdtemp[count] == 0x0D  ||  rdtemp[count] == 0x0A) 
         {
         done = 1 ;
         while (rdtemp[count] == 0x0D  ||  rdtemp[count] == 0x0A) 
            {
            if (++count == UNDERSHOOT)
               return -1 ;
            }
         }
      else if (++count == UNDERSHOOT)
         return -1 ;
      }
   return count;
   }

//*****************************************************************
ulong make_laddr(char* instr)
   {
   ulong ts = ((ulong) FP_SEG(instr)) << 4 ; //lint !e740
   ulong to =  (ulong) FP_OFF(instr) ; //lint !e740
   return ts + to ;
   }

//*****************************************************************
//  NULL-terminates all lines in inbfr, by converting all          
//  CR and LF into NULL.  Also counts the lines and returns count. 
//*****************************************************************
unsigned convert_lines(char* inbfr, unsigned rcount)
   {
   unsigned count = 0 ;    //  output line count
   unsigned bcount = 0 ;   //  input character count
   while (bcount < rcount) 
      {
      if (*inbfr == 0x0D  ||  *inbfr == 0x0A) 
         {
         count++ ;
         while (*inbfr == 0x0D  ||  *inbfr == 0x0A) 
            {
            *inbfr++ = 0 ;
            bcount++ ;
            }
         }
      else 
         {
         inbfr++ ;
         bcount++ ;
         }
      }
   return count ;
   }

//*****************************************************************
//  parse lines from input file.
//  Back file up to 
//*****************************************************************
unsigned fill_search_buffer(FILE* infile)
   {
   int done = 0 ;
   //lint -e740
   unsigned offseti = FP_OFF(readptr) ;   // init value for byte tfr counter
   unsigned offsetf ;
   unsigned count = 0, j ;

   //  fill the readbfr from ref file
   unsigned rlines = fill_read_buffer(infile) ;
   if (rlines == 0) 
      return 0;

   //  DEBUG:
   ulong iaddr = make_laddr(search.bfr[0].instr) ;

   //  now, translate the read buffer into the ref-list buffer
   unsigned lcount = isl_lines ;
   char *sptr = readptr ;
   while (!done) 
      {
      unsigned slen = strlen(sptr) ;

      //  DEBUG:
      {
      ulong saddr = make_laddr(search.bfr[count].instr) ;
      if ((saddr+slen - iaddr) > (ulong) BFR_SIZE) 
         {
         printf("\nSearch overrun:\n") ;
         printf("count = %d\n", count) ;
         printf("iaddr=%ld, saddr=%ld\n", iaddr, saddr) ;
         exit(1) ;
         }
      }
      strcpy(search.bfr[count].instr, sptr) ;

      //  pad short lines with spaces
      if (slen < sizeof(sum_conv)) 
         {
         for (j=slen; j<last_ref_char; j++) 
            search.bfr[count].instr[j] = ' ' ;
         //  now, NULL-terminate the line
         search.bfr[count].instr[last_ref_char] = 0 ;
         }

      //  point to next string in buffer
      sptr += slen ;
      while (*sptr == 0)  sptr++ ;  //  skip NULLs at end of last line

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
         search.tlptr = search.hdptr + (offsetf - offseti) ;
         fsetpos(infile, &search.tlptr) ; //  adjust input-file position
         }
      }

   return count;
   }

//*****************************************************************
//  Read a buffer-worth of raw data into readbfr,
//  do a partial read-and-fill to ensure that it contains
//  a full line at the end,
//  then replace all 0x0D and 0x0A with NULLs.
//  Return a count of lines.
//  
//  This routine reads from the current input file pointer
//*****************************************************************
unsigned fill_read_buffer(FILE* infile)
   {
   //***********************************************************
   //  read data into read buffer and ensure even-line boundary.
   //  This method assumes that the input file has already      
   //  been correctly positioned using fseek().                 
   //***********************************************************
   unsigned rbytes = fread(readptr, 1, ((unsigned) BFR_SIZE)-UNDERSHOOT, infile) ;
   if (rbytes == 0) 
      return 0;

   //***********************************************************
   //                   FILL LAST LINE                          
   //  if last line doesn't already end with a newline,         
   //  read more data to get there, and tack it on the end.     
   //***********************************************************
   char* endptr = readptr + rbytes - 1 ;
   if (*endptr != 0x0D  &&  *endptr != 0x0A)
      {
      unsigned slen = fread(rdtemp, 1, UNDERSHOOT, infile) ;
      if (slen == 0) 
         error_exit(NO_READ_FILE, "reading infile") ;

      unsigned j=0; 
      //  search for newline (it MUST be there!!)
      while (rdtemp[j] != 0x0D  &&  rdtemp[j] != 0x0A)
         {
         j++ ;
         if (j >= UNDERSHOOT) 
            error_exit(BAD_FORMAT, rdtemp) ;
         }
      //  then NULL-out and count the newlines
      while (rdtemp[j] == 0x0D  ||  rdtemp[j] == 0x0A)
         {
         rdtemp[j] = 0 ;
         j++ ;
         if (j >= UNDERSHOOT) 
            error_exit(BAD_FORMAT, rdtemp) ;
         }
      slen = j ;

      //  copy the extra bytes into read buffer
      for (j=0; j<slen; j++) 
         {
         *endptr++ = rdtemp[j] ;
         }
      rbytes += slen ;
      }

   //  NULL-terminate and count the lines in read buffer.
   return convert_lines(readptr, rbytes) ;
   }

//*****************************************************************
void display_logo(void)
   {
   dprints(0, 0, LOGO, logo) ;
   dprints(0, 1, LOGO, dividers) ;
   dprints(0, 2, LOGO, header) ;
   dprints(0, 3, LOGO, dividerd) ;
   }

//*****************************************************************
//  Build the indexed reference list
//*****************************************************************
void build_index(void)
   {
   union sum_conv outList ; 
   char lname[_MAX_PATH] ;
   FILE* idxfile ;
   FILE* infile ;
   fpos_t fpos ;
   char instr[128], outstr[80] ;
   unsigned lflag ;
   char lext, extn[3] = ".x" ;
   unsigned long out_lines = 0L ;

   _makepath(tempstr, ildrive, ilpath, "interrup", "idx") ;
   idxfile = fopen(tempstr, "wb") ;
   if (idxfile == NULL) 
      error_exit(NO_WRITE_FILE, "INTERRUP.IDX") ;

   puts(Version) ;
   puts("Building index file... this will take a couple of minutes") ;

   _makepath(lname, ildrive, ilpath, "interrup", "lst") ;
   infile = fopen(lname, "rb") ;
   if (infile == NULL) //  then combined file does not exist; use parts
      {
      lflag = 0 ;
      lext = 'a' ;
      printf("reading INTERRUP.x sections: ") ;
      _makepath(lname, ildrive, ilpath, "interrup", "a") ;
      infile = fopen(lname, "rb") ;
      if (infile == NULL) 
         {
         fclose(idxfile) ;
         unlink(tempstr) ;
         error_exit(NO_LIST_FILE, lname) ;
         }
      }
   else 
      {
      lflag = 1 ;
      lext = ' ' ;
      printf("reading INTERRUP.LST: ") ;
      }
   fclose(infile) ;

   int done = 0 ;
   while (!done) 
      {
      //  open the next input file
      infile = fopen(lname, "rb") ;
      //  if next file can't be opened, we're done!!
      if (infile == NULL) 
         {
         fclose(idxfile) ;
         printf("\nRef file contains %lu lines\n", out_lines) ;
         return ;
         }
      putchar(lext) ;

      fpos = 0L ;
      //  now that the next List file is open, 
      //  start searching for divider lines
      while ((fgets(instr, 128, infile)) != NULL)
         {
         if (strncmp(instr, "--------", 8) == 0  &&  
             instr[9] == '-'  &&
             instr[8] != '!'
            ) 
            {
            out_lines++ ;

            //  reset the output data field
            memset(outList.idx.data, ' ', 80) ;

            outstr[ 0] = ' ' ;
            outstr[ 1] = instr[10] ; //  INT number
            outstr[ 2] = instr[11] ;
            outstr[ 3] = ' ' ;
            outstr[ 4] = instr[12] ; //  AH contents
            outstr[ 5] = instr[13] ;
            outstr[ 6] = ' ' ;
            outstr[ 7] = instr[14] ; //  AL contents
            outstr[ 8] = instr[15] ;
            outstr[ 9] = ' ' ;
            outstr[10] = instr[8] ; //  classification
            outstr[11] = '>' ;

            outList.idx.file = lext ;
            sprintf(outList.idx.foffset, "%08lX", fpos) ;
            outList.idx.null_term = ' ' ; //  replace NULL with SPACE in file

            //  move instr up to description line
            fgets(instr, 128, infile) ;

            //  Trim line to 80 chars
            int inlen = strlen(instr) ;
            while (instr[inlen-1] == 0x0D  ||  instr[inlen-1] == 0x0A) 
               {
               instr[--inlen] = 0 ;
               }

            strncpy(&outstr[12], &instr[8], 80-13) ;  //  append to outstr
            outstr[80] = 0 ;  //  add safety NULL-terminator
            strcpy(outList.idx.data, outstr) ;
            fprintf(idxfile, "%s\r\n", outList.instr) ;
            }  //  if line matches search pattern, add to index file

         fgetpos(infile, &fpos) ; //  update input-file pointer
         }  //  if input file not yet empty
      fclose(infile) ;
      if (lext == ' ') 
         {
         done = 1 ;
         fclose(idxfile) ;
         }
      else 
         {
         extn[1] = ++lext ;
         _makepath(lname, ildrive, ilpath, "interrup", extn) ;
         }
      }  //  while not done parsing files
   }

