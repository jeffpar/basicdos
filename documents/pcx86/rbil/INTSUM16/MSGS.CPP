//********************************************************************
//  MSGS.CPP - Message and help display functions                     
//                                                                    
//  Copyright (c) 1996 Daniel D. Miller                               
//                                                                    
//  Last Update:  08-31-95 10:10pm                                    
//                                                                    
//  Compile with makefile                                             
//                                                                    
//********************************************************************

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include "intsum.hpp"
#include "keycodes.h"
// #include <memcheck.h>

//*****************************************************************
char* help_str[] = {
Version,
"                   A viewer for Ralf Brown's Interrupt List.         ",
" ",
" Keyboard commands: ",
"  F1, h : This help screen ",
"  F2, s : Search for string ",
"  F3, r : Repeat last search ",
"  F4, t : Save selected topic to a file. (from Ref list only) ",
"  Enter : In reference listing, display detained info on current item. ",
"  Esc   : Exit from program (in reference listing), ",
"          Return to reference listing (in detail listing) ",
" ",
" The first time INTSUM is executed, it will create its custom index file",
" before entering listing mode.  This brief operation will only occur once. ",
" ",
" This program is released as Freeware, though I retain copyright on it.",
" It may be distributed freely.  No money may be charged for it except ",
" reasonable media distribution fees.  To contact the author with bugs, ",
" comments or suggestions, use Internet or SnailNet: ",
" ",
"     Internet:  derelict@netcom.com",
"     SnailNet:  Daniel D. Miller ",
"                36355 BridgePointe Drive",
"                Newark, CA  94560",
   0 } ;

void display_help(void)
   {
   clear_display(HELP_TEXT) ;
   unsigned j = 0 ;
   while (help_str[j] != 0) 
      {
      dprints(1, j, HELP_TEXT, help_str[j]) ;
      j++ ;
      }
   get_key() ;
   }

//*****************************************************************
//  This will display the message pointed to by msg_str,
//  wait for user input (displaying such on the message line),
//  store the user input in global string srchstr[],
//  then restore the message-line text when done.
//  It returns the 0 on successful completion, Key_ESC on escape.
//*****************************************************************
//lint -e743
const char CURSOR_ON  = 'þ' ;
const char CURSOR_OFF = ' ' ;
const clock_t BLINK_RATE = 300 ;

unsigned message_read(char* msg_str, char* instr)
   {
   //  display message for user
   dprints(0, 2, MESSAGE, msg_str) ;

   //  fill remainder of line with input color
   unsigned mlen = strlen(msg_str) ;
   unsigned slen = 79 - mlen ;
   spaces[slen] = 0 ;   //  terminate the spaces string at required length
   dprints(mlen, 2, INPUT, spaces) ;
   spaces[slen] = ' ' ; //  restore the spaces string
   unsigned spos = mlen ;  //  data position on screen

   //  initialize cursor
   int curmode = 1 ;
   dprintc(spos, 2, INPUT, CURSOR_ON) ;
   clock_t clk_time = clock() + BLINK_RATE ;

   //  get user input
   unsigned mpos = 0 ;  //  data position in instr
   unsigned indata ;
   int done = 0 ;
   while (!done) 
      {
      if (key_hit()) 
         {
         //curmode = 0 ;
         dprintc(spos, 2, INPUT, CURSOR_OFF) ;
         indata = get_key() ;
         switch (indata) 
            {
            case Key_ESC:
               //  turn off cursor
               curmode = 0 ;
               dprintc(spos, 2, INPUT, CURSOR_OFF) ;
               done = -1 ;
               break;

            case Key_ENTER:
               *(instr+mpos) = 0 ;  //  NULL-terminate the string
               done = 1 ;
               indata = 0 ;
               break;

            case Key_BSPACE:
               if (mpos > 0) 
                  {
                  mpos-- ;
                  *(instr+mpos) = 0 ;  //  NULL-terminate the string
                  dprintc(--spos, 2, INPUT, ' ') ;
                  }
               break;

            default:
               //  this won't work for ALL characters, 
               //  but it will work for normal ASCII chars.
               char outchr = (char) (indata & 0x00FF) ;
               if (mpos < slen) 
                  {
                  *(instr+mpos) = outchr ;
                  mpos++ ;
                  dprintc(spos++, 2, INPUT, outchr) ;
                  }
               break;
            }
         //curmode = 1 ;
         dprintc(spos, 2, INPUT, CURSOR_ON) ;
         // clk_time = clock() + BLINK_RATE ;
         }  //  if a key was pressed, read it

      //  If no key is pressed, update cursor
      else 
         {
         if (clock() > clk_time) 
            {
            if (curmode == 0) 
               {
               curmode = 1 ;
               dprintc(spos, 2, INPUT, CURSOR_ON) ;
               clk_time = clock() + BLINK_RATE ;
               }
            else 
               {
               curmode = 0 ;
               dprintc(spos, 2, INPUT, CURSOR_OFF) ;
               clk_time = clock() + BLINK_RATE ;
               }
            }
         }
      }

   //  restore the message line to normal data
   dprints(0, 2, LOGO, header) ;
   return indata ;   //lint !e644
   }

//*****************************************************************
//  This will display the message pointed to by msg_str,
//  wait for user keystroke,
//  then restore the message-line text.
//*****************************************************************
void message_show(char* msg_str)
   {
   //  display message for user
   dprints(0, 2, MESSAGE, msg_str) ;

   //  fill remainder of line with input color
   unsigned mlen = strlen(msg_str) ;
   unsigned slen = 79 - mlen ;
   spaces[slen] = 0 ;   //  terminate the spaces string at required length
   dprints(mlen, 2, MESSAGE, spaces) ;
   spaces[slen] = ' ' ; //  restore the spaces string

   get_key() ;
   //  restore the message line to normal data
   dprints(0, 2, LOGO, header) ;
   }


