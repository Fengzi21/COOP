#include <string.h>
#include <stdio.h>

#ifdef HAS_CFITSIO
#include "fitsio.h"
#endif

#include "constants.h"

void coop_fits_read_header_to_string_(char* filename, char* cards, int* nkeys){
#ifdef HAS_CFITSIO
  fitsfile *fptr;         
  char card[FLEN_CARD]; 
  int status, ii; 
  status = 0; /* MUST initialize status */
  fits_open_file(&fptr, filename, READONLY, &status);
  fits_get_hdrspace(fptr, nkeys, NULL, &status);
  for (ii = 1; ii <= *nkeys; ii++)  { 
    fits_read_record(fptr, ii, card, &status); /* read keyword */
    if(ii == 1)
      strcpy(cards, card);
    else
      strcat(cards, card);//    printf("%s\n", card);
    strcat(cards, "\n");//    printf("%s\n", card);
  }
  fits_close_file(fptr, &status);
    
  if (status)          /* print any error messages */
    fits_report_error(stderr, status);
#else
  printf("CFITSIO library is missing. Please change your configure file.");
#endif
}



void coop_fits_get_dimension_(char* filename, int* nx,int* ny, int* bytes){
#ifdef HAS_CFITSIO
  fitsfile *fptr;         
  int status, idim;
  long naxes[2];
  status = 0; /* MUST initialize status */
  fits_open_file(&fptr, filename, READONLY, &status);
  fits_get_img_dim(fptr, & idim, & status);
  if(idim != 2) {
    *nx = 0;
    *ny = 0;
    *bytes = 0;
  }
  else{
    fits_get_img_size(fptr, idim, naxes, &status);
    *nx = naxes[0];
    *ny = naxes[1];
    fits_get_img_type(fptr, bytes, &status);
    *bytes = - (*bytes) / 8;
  }
  fits_close_file(fptr, &status);
  if (status)          /* print any error messages */
    fits_report_error(stderr, status);

#else
  printf("CFITSIO library is missing. Please change your configure file.");
#endif

}


void coop_fits_get_double_data_(char * filename, double* data, long * n){
#ifdef HAS_CFITSIO
  fitsfile *fptr;         
  int status;
  long fpixel[2];
  LONGLONG nelements;
   fpixel[0] = 1;
   fpixel[1] = 1;
   status = 0; /* MUST initialize status */
   nelements = *n;
   fits_open_file(&fptr, filename, READONLY, &status);
   fits_read_pix(fptr, TDOUBLE, fpixel, nelements, NULL, data, NULL, &status);  
   fits_close_file(fptr, &status);
   if (status)          /* print any error messages */
     fits_report_error(stderr, status);
#else
  printf("CFITSIO library is missing. Please change your configure file.");
#endif
}


void coop_fits_get_float_data_(char * filename, float * data, long * n){
#ifdef HAS_CFITSIO
  fitsfile *fptr;         
  int status;
  long fpixel[2];
  LONGLONG nelements;
   fpixel[0] = 1;
   fpixel[1] = 1;
   status = 0; /* MUST initialize status */
   nelements = *n;
   fits_open_file(&fptr, filename, READONLY, &status);
   fits_read_pix(fptr, TDOUBLE, fpixel, nelements, NULL, data, NULL, &status);  
   fits_close_file(fptr, &status);
   if (status)          /* print any error messages */
     fits_report_error(stderr, status);
#else
  printf("CFITSIO library is missing. Please change your configure file.");
#endif
}


void coop_fits_write_image_(char * filename, int *nkeys, char *keys, char *values, int dtypes[], double * data, int * nx, int * ny) {
#ifdef HAS_CFITSIO
  fitsfile *fptr;       /* pointer to the FITS file; defined in fitsio.h */
  int status, i, keylen, vallen;
  long  fpixel, naxis, nelements;
  long naxes[2];   /* image is 300 pixels wide by 200 rows */
  int  ivalue;
  float  fvalue;
  char thekey[80];
  char theval[80];
  char * keyloc;
  char * valloc;
  int true=1, false=0;
  fpixel = 1;
  naxis = 2;
  naxes[0] = *nx;
  naxes[1] = *ny;
  status = 0;    
  fits_create_file(&fptr, filename,  &status); 
  fits_create_img(fptr, SHORT_IMG, naxis, naxes, &status);
  keyloc = keys;
  valloc = values;
  keylen = strchr(keyloc, '\n') - keyloc;
  vallen = strchr(valloc, '\n') - valloc;

  for( i = 0; i< *nkeys; i++){
    strncpy(thekey, keyloc, keylen);
    strncpy(theval, valloc, vallen);
    thekey[keylen] = '\0';
    theval[vallen] = '\0';
    if(dtypes[i] == COOP_FORMAT_STRING)
      fits_update_key(fptr, TSTRING, thekey, theval, NULL,  &status);
    else if(dtypes[i] == COOP_FORMAT_LOGICAL){
      if(theval[0] == 'T'){
	fits_update_key(fptr, TLOGICAL, thekey, &true, NULL,  &status);
      }
      else
	fits_update_key(fptr, TLOGICAL, thekey, &false, NULL,  &status);
    }
    else if(dtypes[i] == COOP_FORMAT_INTEGER){
      ivalue = atoi(theval); 
      fits_update_key(fptr, TINT, thekey, &ivalue, NULL,  &status);}
    else if(dtypes[i] == COOP_FORMAT_FLOAT ){
      fvalue = atof(theval);
      fits_update_key(fptr, TFLOAT, thekey, &fvalue, NULL,  &status);}
    keyloc = keyloc + keylen+1;
    valloc = valloc + vallen+1;
    keylen = strchr(keyloc, '\n') - keyloc;
    vallen = strchr(valloc, '\n') - valloc;
  }
  nelements = naxes[0] * naxes[1];      
  fits_write_img(fptr, TDOUBLE, fpixel, nelements, data, &status);
  fits_close_file(fptr, &status);       
  if(status){
    fits_report_error(stderr, status); }
#else
  printf("Cannot find CFITSIO library.");
#endif
 }
