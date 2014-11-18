program hastack_prog
  use coop_wrapper_utils
  use coop_fitswrap_mod
  use coop_sphere_mod
  use coop_healpix_mod
  use head_fits
  use fitstools
  use pix_tools
  use alm_tools
  implicit none
#include "constants.h"
  COOP_INT, parameter::n_sim = 1000
  COOP_UNKNOWN_STRING, parameter::spot_type = "Pmax"
  COOP_UNKNOWN_STRING, parameter::stack_type = "QU"
  COOP_REAL, parameter::patch_size = 5.d0*coop_SI_degree
  COOP_UNKNOWN_STRING, parameter::output_dir = "hc_r5f30n1024"
  
  COOP_UNKNOWN_STRING, parameter::prefix = output_dir//"/"
  COOP_INT, parameter::mmax = 4
  COOP_REAL, parameter::fwhm_arcmin = 30.d0
  COOP_REAL, parameter::fwhm_in = 10.d0
  COOP_UNKNOWN_STRING, parameter::postfix =   "_010a_1024.fits"

  COOP_STRING::allprefix
  COOP_UNKNOWN_STRING, parameter::mapdir = "/mnt/scratch-lustre/zqhuang/scratch-3month/zqhuang/"
  COOP_REAL,parameter::fwhm = coop_SI_arcmin * sqrt(fwhm_arcmin**2-fwhm_in**2)
  COOP_REAL, parameter::threshold = 0
  COOP_REAL, parameter::dr = coop_SI_arcmin * max(fwhm_arcmin/4.d0, fwhm_in/2.d0)
  COOP_INT, parameter::n = nint(patch_size/dr)

  COOP_UNKNOWN_STRING, parameter::imap_file  = "planck14/dx11_v2_smica_int_cmb"//postfix
  COOP_UNKNOWN_STRING, parameter::polmap_file  = "planck14/dx11_v2_smica_pol_case1_cmb_hp_20_40"//postfix
  COOP_UNKNOWN_STRING, parameter::imask_file  = "planck14/dx11_v2_common_int_mask"//postfix
  COOP_UNKNOWN_STRING, parameter::polmask_file  ="planck14/dx11_v2_common_pol_mask"//postfix

  type(coop_healpix_maps)::polmask, imask, noise, imap, polmap, tmpmap
  type(coop_healpix_patch)::patch_s, patch_n
  integer,parameter::scan_nside = 4
  integer,parameter::scan_npix = scan_nside**2*6
  integer run_id, i, ind, j, lmax
  COOP_REAL   hdir(2)
  COOP_STRING::fr_file
  type(coop_list_integer)::listpix
  type(coop_list_real)::listangle
  type(coop_file) fp
  logical::i_loaded = .false.
  logical::pol_loaded = .false.
  
  call coop_MPI_init()
  lmax = min(ceiling(3.d0/(fwhm_arcmin*coop_SI_arcmin*coop_sigma_by_fwhm)), 2048, coop_healpix_default_lmax)
  if(iargc() .ge. 1)then
     run_id = coop_str2int(coop_InputArgs(1))
  else
     run_id = coop_MPI_Rank()
  endif
  call sleep(run_id*3)  !!sleep for 3 seconds so that files are not read simultaneously
  if(run_id .ge.  scan_npix)then
     write(*,*) "run id must not exceed ", scan_nside**2*12 - 1
     call coop_MPI_Abort()
  endif
  call pix2ang_ring(scan_nside, run_id, hdir(1), hdir(2))

  !!read masks
  call imask%read(imask_file, nmaps_wanted = 1, spin = (/ 0 /) )
  call polmask%read(polmask_file, nmaps_wanted = 1, spin = (/ 0 /) )
  
  call patch_n%init(stack_type, n, dr, mmax = mmax)
  patch_s = patch_n

  allprefix = prefix//stack_type//"_on_"//spot_type//"_fr_"//COOP_STR_OF(scan_nside)//"_"

  if(run_id.eq.0)then
     call fp%open(trim(allprefix)//"info.txt", "w")
     write(fp%unit,*) n, patch_n%nmaps, dr/coop_SI_arcmin
     call fp%close()
  endif
  fr_file = trim(allprefix)//COOP_STR_OF(run_id)//".dat"


  ind = -1
  if(.not. coop_file_exists(trim(fr_file)))goto 200
  call fp%open(trim(fr_file), "ru")
  do
     read(fp%unit, ERR=100, END=100) i
     read(fp%unit, ERR=100, END=100) patch_n%fr
     read(fp%unit, ERR=100, END=100) patch_s%fr
     if(i.ne.ind+1) call cooP_MPI_Abort("fr file broken")
     ind = i
     if(ind .ge. n_sim) exit
  enddo
100 write(*,*) "Loaded "//trim(coop_num2str(ind+1))//" maps from checkpoint"
  call fp%close()
200 call fp%open(trim(fr_file), "u")
  do i=0, ind
     read(fp%unit, ERR=100, END=100) j
     read(fp%unit, ERR=100, END=100) patch_n%fr
     read(fp%unit, ERR=100, END=100) patch_s%fr
     if(j.ne.i)call cooP_MPI_Abort("fr file broken")
  enddo
  do while(ind .lt. n_sim)
     i_loaded = .false.
     pol_loaded = .false.
     ind = ind + 1
     print*, "stacking map #"//COOP_STR_OF(ind)
     select case(trim(spot_type))
     case("Tmax", "PTmax", "Tmax_QTUTOrient", "Tmin", "PTmin", "Tmin_QTUTOrient")
        call load_imap(ind)
        call imap%get_listpix(listpix, listangle, spot_type, threshold, imask)
     case("Pmax", "Pmin")
        call load_polmap(ind)
        call polmap%get_listpix(listpix, listangle, spot_type, threshold, polmask)
     case default
        print*, trim(spot_type)        
        stop "Unknown spot type"
     end select
     select case(stack_type)
     case("T")
        call load_imap(ind)
        call imap%stack_north_south(patch_n, patch_s, listpix, listangle, hdir, imask)
     case("QU", "QrUr")
        call load_polmap(ind)
        call polmap%stack_north_south(patch_n, patch_s, listpix, listangle, hdir, polmask)
     case default
        print*, trim(stack_type)
        stop "Unknown stack type"
     end select

     call patch_n%get_all_radial_profiles()
     call patch_s%get_all_radial_profiles()
     write(fp%unit) ind
     write(fp%unit) patch_n%fr
     write(fp%unit) patch_s%fr
     flush(fp%unit)
  enddo
  call fp%close()
  call coop_MPI_Finalize()

contains

  subroutine load_imap(i)
    COOP_INT i, nm
    COOP_INT,dimension(:),allocatable::spin
    if(i_loaded) return
    select case(trim(spot_type))
    case("Tmax_QTUTOrient", "Tmin_QTUTOrient", "PTmax", "PTmin")
       nm = 3
    case default
       nm = 1
    end select
    allocate(spin(nm))
    spin(1) = 0
    if(nm.gt.1) spin(2:3) = 2
    if(i.eq.0)then
       call imap%read(filename = trim(imap_file), nmaps_wanted = nm , spin = spin , nmaps_to_read = 1 )
       imap%map(:, 1) = imap%map(:, 1)*imask%map(:, 1)
       if(fwhm.ge.coop_SI_arcmin)    call imap%smooth(fwhm, l_upper = lmax)
       noise = imap
    else
       call imap%read(trim(sim_file_name_cmb_imap(i)), nmaps_wanted = nm , spin = spin , nmaps_to_read = 1 )
       call noise%read(trim(sim_file_name_noise_imap(i)), nmaps_wanted = nm , spin = spin, nmaps_to_read = 1 )
       imap%map(:, 1) = (imap%map(:, 1) + noise%map(:, 1))*imask%map(:, 1)
       if(fwhm.ge.coop_SI_arcmin)    call imap%smooth(fwhm, l_upper = lmax)
    endif
    deallocate(spin)
    if(nm.gt.1)call imap%iqu2TQTUT()
  end subroutine load_imap


  subroutine load_polmap(i)
    COOP_INT i
    if(pol_loaded)return
    if(i.eq.0)then
       call polmap%read(trim(polmap_file), spin = (/2 , 2 /) , nmaps_wanted = 2  )
       polmap%map(:, 1) = polmap%map(:, 1)*polmask%map(:, 1)
       polmap%map(:, 2) = polmap%map(:, 2)*polmask%map(:, 1)
       if(fwhm.ge.coop_SI_arcmin)call polmap%smooth(fwhm, l_upper = lmax)
    else
       call polmap%read(trim(sim_file_name_cmb_polmap(i)), spin = (/2 , 2 /) , nmaps_wanted = 2  )
       call noise%read(trim(sim_file_name_noise_polmap(i)), spin = (/2 , 2 /) , nmaps_wanted = 2 )
       polmap%map(:, 1) = (polmap%map(:, 1) + noise%map(:, 1))*polmask%map(:, 1)
       polmap%map(:, 2) = (polmap%map(:, 2) + noise%map(:, 2))*polmask%map(:, 1)
       if(fwhm.ge.coop_SI_arcmin)call polmap%smooth(fwhm, l_upper = lmax)
    endif
  end subroutine load_polmap


  function sim_file_name_cmb_imap(i)
    COOP_INT i
    COOP_STRING sim_file_name_cmb_imap
    sim_file_name_cmb_imap = mapdir//"cmb/int/dx11_v2_smica_int_cmb_mc_"//trim(coop_Ndigits(i-1, 5))//postfix
  end function sim_file_name_cmb_imap

  function sim_file_name_noise_imap(i)
    COOP_INT i
    COOP_STRING sim_file_name_noise_imap
    sim_file_name_noise_imap = mapdir//"noise/int/dx11_v2_smica_int_noise_mc_"//trim(coop_Ndigits(i-1, 5))//postfix
  end function sim_file_name_noise_imap


  function sim_file_name_cmb_polmap(i)
    COOP_INT i
    COOP_STRING sim_file_name_cmb_polmap
    sim_file_name_cmb_polmap = mapdir//"cmb/pol/dx11_v2_smica_pol_case1_cmb_mc_"//trim(coop_Ndigits(i-1, 5))//"_hp_20_40"//postfix
  end function sim_file_name_cmb_polmap

  function sim_file_name_noise_polmap(i)
    COOP_INT i
    COOP_STRING sim_file_name_noise_polmap
    sim_file_name_noise_polmap = mapdir//"noise/pol/dx11_v2_smica_pol_case1_noise_mc_"//trim(coop_Ndigits(i-1, 5))//"_hp_20_40"//postfix
  end function sim_file_name_noise_polmap

end program hastack_prog
