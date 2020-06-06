//********************************************************************
//                                                                    
//  CONFIG.CPP -  INI-file handling routines                          
//                                                                    
//  Copyright (c) 1996 Daniel D. Miller                               
//                                                                    
//  Last Update:  10-14-95 11:37am                                    
//                                                                    
//  Compile with makefile                                             
//                                                                    
//********************************************************************
#include <stdio.h>
#include <stdlib.h>     //  strtol(), _splitpath(), _makepath()
#include <string.h>
#include "intsum.hpp"
#include "err_exit.hpp"
// #include <memcheck.h>

static char parse_text[81] ;

//********************************************************************
//  .INI-file strings
//  Note:  INI groups will not be implemented in this application
//********************************************************************

uchar BORDER    = 0x06 ;
uchar LOGO      = 0x13 ;
uchar MAIN_TEXT = 0x02 ;
uchar SELECTED  = 0x31 ;
uchar FILENAME  = 0x1B ;
uchar MESSAGE   = 0x1C ;
uchar INPUT     = 0x34 ;
uchar HELP_TEXT = 0x07 ;

struct config_opt {
   char* name ;
   uchar* attr ;
   } ;

//  entries in [text]
config_opt text_group[] = {
{ "border", &BORDER },
{ "logo", &LOGO },
{ "main_text", &MAIN_TEXT },
{ "selected", &SELECTED },
{ "filename", &FILENAME },
{ "message", &MESSAGE },
{ "input", &INPUT },
{ "help_text", &HELP_TEXT },
{ "video_seg", NULL },
{ "list_dir", NULL },
{ NULL, NULL } } ;

//***************  function prototypes  ***************
static int  write_ini_values(char* ini_name);
static int  init_config(char* ini_name);
static void parse_line(char* tptr);

//**************************************************************
//  If INTSUM.INI exists in the appropriate directory,          
//  read it.  Otherwise, write a default file in that place.    
//**************************************************************
int read_ini_file(void)
   {
   char ini_name[128] ; //  
   int result = DATA_OKAY ;

   _makepath (ini_name, inidrive, inipath, "intsum", ".INI") ;

   //****************************************************
   //  now, we believe we have determined an INI name.   
   //  Try to open the file, and abort if it doesn't     
   //  exist.                                            
   //****************************************************
   FILE* initest = fopen(ini_name, "rt") ;
   if (initest == NULL)
      {
      //************************************************
      //  intsum.INI does not already exist;
      //  write the default file.
      //************************************************
      result = write_ini_values(ini_name) ;
      }
   else
      {
      //************************************************
      //  intsum.INI already exists
      //************************************************
      fclose(initest) ;   //  file is there - continue
      result = init_config(ini_name) ;
      }
   return result ;
   }

//**************************************************************
static int write_ini_values(char* ini_name)
   {
   FILE* inifile = fopen(ini_name, "wt") ;
   if (inifile == NULL)
      return(NO_WRITE_FILE) ;

fprintf(inifile, "; INTSUM.INI - default configuration file for INTSUM.EXE\n") ;
fprintf(inifile, "; All attributes must be in two-digit hex format, preceded by 0x,\n") ;
fprintf(inifile, "; as shown below.  \n") ;
fprintf(inifile, "; Comments are marked with a semicolon.  All data following a\n") ;
fprintf(inifile, "; semicolon is ignored to end of line.\n") ;
fprintf(inifile, "\n") ;
fprintf(inifile, "BORDER       = 0x%02X ; window borders\n", BORDER) ;
fprintf(inifile, "LOGO         = 0x%02X ; window banners\n", LOGO) ;
fprintf(inifile, "MAIN_TEXT    = 0x%02X ; primary text color\n", MAIN_TEXT) ;
fprintf(inifile, "SELECTED     = 0x%02X ; current cursor line\n", SELECTED) ;
fprintf(inifile, "FILENAME     = 0x%02X ; filename in list window\n", FILENAME) ;
fprintf(inifile, "MESSAGE      = 0x%02X ; status message color\n", MESSAGE) ;
fprintf(inifile, "INPUT        = 0x%02X ; user input fields\n", INPUT) ;
fprintf(inifile, "HELP_TEXT    = 0x%02X ; help-screen color\n", HELP_TEXT) ;
fprintf(inifile, "\n") ;
fprintf(inifile, "VIDEO_SEG    = 0x%04X ; Video segment: 0xB800 or 0xB000\n", 
                  get_video_seg()) ;
fprintf(inifile, "\n") ;
fprintf(inifile, ";  Next line is path to Interrupt List files\n") ;
fprintf(inifile, ";  NOTE:  This path MUST end with a backslash!!\n") ;
fprintf(inifile, "LIST_DIR     = %s%s ; path to Interrupt List files\n", 
                     ildrive,ilpath) ;

   fclose(inifile) ;
   return END_OF_FILE ;
   }

//**************************************************************
static int init_config(char* ini_name)
   {
   if (ini_name == NULL)
      error_exit(NO_INI_FILE, NULL) ;
      
   FILE* inifile = fopen(ini_name, "rt") ;
   if (inifile == NULL)
      error_exit(NO_INI_FILE, ini_name) ;

   //****************************************************
   //  Each subsequent call to parse_ini will return one 
   //  line from the file, or END_OF_FILE when finished. 
   //****************************************************
   while (fgets(parse_text, 80, inifile) != NULL)
      {
      int len = strlen(parse_text) ;
      if (parse_text[len-1] == 0x0D  ||  parse_text[len-1] == 0x0A) 
         parse_text[len-1] = NULL ; //  strip off newline char
      parse_line(parse_text) ;   //  remove comments, spaces, tabs

      if (strlen(parse_text) > 0)  //  get next line (skip blank line)
         {
         //***********************************************
         //  separate option name and value
         //***********************************************
         char* strptr = strchr(parse_text, '=') ;
         if (strptr == NULL)
            return BAD_FORMAT ;
         *strptr++ = NULL ;

         //***********************************************
         //  search for optname in option-name list
         //***********************************************
         config_opt *textptr = &text_group[0] ;
         int j = 0 ;
         int done = 0 ;
         while (!done) 
            {
            //  if at end of config-options list, 
            //  go to next line from input file.
            //  This implies an unknown option, which we just ignore
            if (textptr->name == NULL)
               done = 1 ;

            //  if matching line is found, process it
            else if (strcmp(textptr->name, parse_text) == 0)
               {
               //  if attribute is NULL, this is not a color item.
               if (textptr->attr == NULL) 
                  {
                  //  if current element is video_seg, 
                  //  call the setting function as well.
                  if (strcmp(textptr->name, "video_seg") == 0)
                     {
                     unsigned vseg = (unsigned) strtol(strptr, NULL, 0) ;
                     select_video_seg(vseg) ;
                     }
                  else 
                     {
                     // strcpy(int_list_dir, strptr) ;
                     _splitpath(strptr, ildrive, ilpath, NULL, NULL) ;
                     }
                  }

               //  if attrib is NOT NULL, it's a color item
               else 
                  {
                  *(textptr->attr) = (uchar) strtol(strptr, NULL, 0) ;
                  }
               done = 1 ;
               }

            //  if matching line not yet found, try next line item
            else 
               {
               textptr = &text_group[++j] ;
               }
            }
         }  //  if current line is not blank after stripping comments
      }  //  while looping thru ini-file
   fclose(inifile) ;
   return DATA_OKAY ;
   }

//*********************************************************************
//  This routine parses the string pointed to by (tptr).               
//  The following tasks are performed:                                 
//                                                                     
//     - remove everything from the first semicolon.                   
//     - remove all spaces and tabs between SOL and EOL.               
//     - convert remaining line to lower case.                         
//                                                                     
//*********************************************************************
static void parse_line(char* tptr)
   {
   int head=0, tail=0, done=0 ;
   do
      {
      if ((*(tptr+tail) == ';') || (*(tptr+tail) == NULL))
         {
         *(tptr+head) = NULL ;
         done = 1 ;
         }
      else if ((*(tptr+tail) == ' ') || (*(tptr+tail) == 0x09 ))
         tail++ ;
      else
         {
         if (tail > head)
            *(tptr+head) = *(tptr+tail) ;
         head++ ;
         tail++ ;
         }
      }
   while (!done);
   strlwr(tptr) ;
   }

