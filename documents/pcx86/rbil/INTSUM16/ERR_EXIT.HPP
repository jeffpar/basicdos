//*********************************************************
//  ERR_EXIT.HPP - Header for semi-standard error handler  
//                                                         
//  Written by:   Daniel D. Miller                         
//                                                         
//  Last Update:  06-23-95 08:23am                         
//                                                         
//*********************************************************

enum error_code {
USAGE=0,
OUT_OF_MEMORY,
NO_LIST_FILE,
NO_READ_FILE,
NO_WRITE_FILE,
BAD_FORMAT,
BAD_USAGE_LEN,
BAD_SEARCH,
NO_INI_FILE,
NO_DEBUG_FILE,
BAD_REV_SEARCH,
OLD_DOS_VERSION,
INV_ERRCODE } ;

extern char *errmsg[] ;

void error_exit(int err_code, char* errstr);

