program test
  use coop_wrapper_utils
  use coop_fitswrap_mod
  use coop_sphere_mod
  use coop_healpix_mod
#ifdef HAS_HEALPIX
  use head_fits
  use fitstools
  use pix_tools
  use alm_tools
  use udgrade_nr
  use coord_v_convert,only:coordsys2euler_zyz
#endif  
  implicit none
#include "constants.h"
  COOP_INT, parameter::lmax = 30
  type(coop_file)::fp
  type(coop_asy)::fig
  COOP_SINGLE, parameter::linewidth = 0.5
  COOP_STRING::line
  COOP_INT::l, i , ic
  COOP_REAL::tmp
  COOP_REAL::ells(2:lmax), Cls(2:lmax), Cls_fiducial(2:lmax), delta_Cls(2:lmax)
  call coop_set_uniform(lmax-1, ells, 2.d0, dble(lmax))
  call fig%open("lowl_Cl.txt")
  call fig%init(xlabel = "$\ell$", ylabel = "$\frac{\ell(\ell +1)}{2\pi}C_l \, (\mu K^2)$", width = 6., height = 5.2, xmin = 1.5, xmax = 30.5, ymin = 0., ymax = 2000., doclip=.true.)

  ic = 1
  call fp%open("clsout/clsout_NONE.dat", "r")
  read(fp%unit, "(A)")line
  do l = 2, lmax
     read(fp%unit, *) i, Cls_fiducial(l), Cls(l), delta_Cls(l)
     if(i.ne. l) stop "error"
  enddo
  call fp%close()
  call fig%curve(x = ells, y = Cls_fiducial, legend="$\Lambda$CDM", color = trim(fig%color(ic)), linetype = trim(fig%linetype(ic)), linewidth = 2.)
  ic = ic + 1
  call fig%curve(x = ells, y = Cls, legend="NONE", color = "gray", linetype = trim(fig%linetype(2)),linewidth = 1.5)
  call fig%errorbars(x = ells, y = Cls, dy = delta_Cls, color = "gray_solid_1",  barsize = 5., center_color = "gray_solid_4")




  call fp%open("clsout/clsout_NEP.dat", "r")
  read(fp%unit, "(A)")line
  do l = 2, lmax
     read(fp%unit, *) i, Cls_fiducial(l), Cls(l), tmp
     if(i.ne. l) stop "error"
  enddo
  call fp%close()
  call fig%curve(x = ells, y = Cls, legend="NEP", color = trim(fig%color(ic)), linetype = trim(fig%linetype(ic)),linewidth = linewidth)
  ic = ic + 1

  call fp%open("clsout/clsout_SEP.dat", "r")
  read(fp%unit, "(A)")line
  do l = 2, lmax
     read(fp%unit, *) i, Cls_fiducial(l), Cls(l), tmp
     if(i.ne. l) stop "error"
  enddo
  call fp%close()
  call fig%curve(x = ells, y = Cls, legend="SEP", color = "darkgreen", linetype = trim(fig%linetype(ic)),linewidth = linewidth)
  ic = ic + 1
  call fp%open("clsout/clsout_NGP.dat", "r")
  read(fp%unit, "(A)")line
  do l = 2, lmax
     read(fp%unit, *) i, Cls_fiducial(l), Cls(l), tmp
     if(i.ne. l) stop "error"
  enddo
  call fp%close()
  call fig%curve(x = ells, y = Cls, legend="NGP", color = trim(fig%color(ic)), linetype = trim(fig%linetype(ic)),linewidth = linewidth)
  ic = ic + 1

  call fp%open("clsout/clsout_SGP.dat", "r")
  read(fp%unit, "(A)")line
  do l = 2, lmax
     read(fp%unit, *) i, Cls_fiducial(l), Cls(l), tmp
     if(i.ne. l) stop "error"
  enddo
  call fp%close()
  call fig%curve(x = ells, y = Cls, legend="SGP", color = trim(fig%color(ic)), linetype = trim(fig%linetype(ic)),linewidth = linewidth)
  ic = ic + 1
  
!!$  call fp%open("clsout/clsout_NCP.dat", "r")
!!$  read(fp%unit, "(A)")line
!!$  do l = 2, lmax
!!$     read(fp%unit, *) i, Cls_fiducial(l), Cls(l), tmp
!!$     if(i.ne. l) stop "error"
!!$  enddo
!!$  call fp%close()
!!$  call fig%curve(x = ells, y = Cls, legend="NCP", color = trim(fig%color(ic)), linetype = trim(fig%linetype(ic)),linewidth = linewidth)
!!$  ic = ic + 1
!!$
!!$
!!$  call fp%open("clsout/clsout_SCP.dat", "r")
!!$  read(fp%unit, "(A)")line
!!$  do l = 2, lmax
!!$     read(fp%unit, *) i, Cls_fiducial(l), Cls(l), tmp
!!$     if(i.ne. l) stop "error"
!!$  enddo
!!$  call fp%close()
!!$  call fig%curve(x = ells, y = Cls, legend="SCP", color = trim(fig%color(ic)), linetype = trim(fig%linetype(ic)),linewidth = linewidth)
!!$  ic = ic + 1

  call fp%open("clsout/clsout_COLDSPOT.dat", "r")
  read(fp%unit, "(A)")line
  do l = 2, lmax
     read(fp%unit, *) i, Cls_fiducial(l), Cls(l), tmp
     if(i.ne. l) stop "error"
  enddo
  call fp%close()
  call fig%curve(x = ells, y = Cls, legend="Cold Spot", color = "blue", linetype = "solid", linewidth = 1.5)
  
  call fig%legend(0.25, 0.92, 2, box = .false.)
  
end program test
