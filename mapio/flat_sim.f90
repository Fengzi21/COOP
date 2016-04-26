program test
  use coop_wrapper_utils
  use coop_fitswrap_mod
  use coop_healpix_mod
  use coop_sphere_mod
  use coop_fitsio_mod
  implicit none
#include "constants.h"
  character(LEN=*),parameter::mapdir = "act16/"
  COOP_UNKNOWN_STRING,parameter::beam_file = mapdir//"beam_7ar2.txt"
  COOP_INT,parameter::lmin =   200
  COOP_INT,parameter::lmax = 3000
  COOP_REAL,parameter::reg_limit = 0.001d0
  COOP_INT::isim
  type(coop_fits_image_cea)::tmap, emap, bmap, noise, qmap, umap
  COOP_REAL::fwhm_arcmin = 0.5
  COOP_REAL::Cls(lmin:lmax,6),junk, bl(lmin:lmax), norm
  COOP_INT::l, il
  type(coop_file)::fp
  call coop_get_command_line_argument(key = "isim", arg = isim, default = 1)
  call coop_random_init()
  call fp%open_skip_comments(beam_file)
  do l = 0, lmin-1
     read(fp%unit, *) il, junk
  enddo
  do l=lmin, lmax
     read(fp%unit, *) il, bl(l)
     if(il.ne.l) stop "error in beam file"
  enddo
  call fp%close()
  Cls = 0.d0
  call fp%open_skip_comments("teb_lensedCls.dat")
  do l=2, lmin-1
     read(fp%unit, *) il, junk
  enddo
  do l=lmin, lmax
     read(fp%unit, *) il, Cls(l, coop_TEB_index_TT), Cls(l, coop_TEB_index_EE), Cls(l, coop_TEB_index_BB), Cls(l, coop_TEB_index_TE)
     if(il.ne.l) stop "error in cl file"
     norm =  coop_2pi/l/(l+1.d0)*coop_Gaussian_filter(fwhm_arcmin = fwhm_arcmin, l=l)**2*bl(l)**2
     Cls(l,:) = Cls(l,:)*norm
  enddo
  call fp%close()
  call tmap%open(mapdir//"act_matcoadd_I.fits")
  emap = tmap
  bmap = tmap
  qmap = tmap
  umap = tmap
  call coop_fits_image_cea_simulate_TEB(lmin=lmin, lmax=lmax, Cls=Cls, tmap = tmap, emap = emap, bmap = bmap, qmap=qmap, umap =umap)
  call tmap%write(mapdir//"simteb_"//COOP_STR_OF(isim)//"_I.fits")
  call qmap%write(mapdir//"simteb_"//COOP_STR_OF(isim)//"_Q.fits")
  call umap%write(mapdir//"simteb_"//COOP_STR_OF(isim)//"_U.fits")

  call emap%free()
  call bmap%free()
end program test
