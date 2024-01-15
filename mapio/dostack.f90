program Stacking_Maps
  use coop_wrapper_utils
  use coop_healpix_mod
  use coop_stacking_mod
  use coop_gstack_mod
  implicit none
#include "constants.h"
#ifdef HAS_HEALPIX
  logical::remove_mono = .false.
  logical::randrot, want_pdf, norm_to_corr
  COOP_REAL::norm_power 
  COOP_STRING::mask_file, peak_file, map_file, output, imask_file, polmask_file, field_name, params_file
  COOP_INT::n = 100
  COOP_REAL::r_degree, dr
  type(coop_stacking_options)::sto
  type(coop_healpix_patch)::patch
  type(coop_healpix_maps)::hgm, mask, pmap
  COOP_INT i, m
  COOP_REAL::zmin1, zmax1, zmin2, zmax2
  type(coop_asy)::fig
  COOP_REAL::tmax
  if(iargc().le.0)then
     write(*,"(A)") "----------------------------------------------------------"     
     write(*,"(A)") "Syntax:"
     write(*,"(A)") "./Stack params.ini"
     write(*,"(A)") "or if you want run from the command line"          
     write(*,"(A)") "./Stack -map MAP_FILE -peaks PEAK_FILE  -field [T|E|B|zeta|QU|QrUr]"
     write(*,"(A)") "----------------------------------------------------------"
     write(*,"(A)") "other options are:"
     write(*,"(A)") "-out OUTPUT_FILE"     
     write(*,"(A)") "-mask [MASK_FILE|NONE|'']"
     write(*,"(A)") "-radius RADIUS_IN_DEGREE"
     write(*,"(A)") "-res RESOLUTION(10-200)"
     write(*,"(A)") "-width WIDTH_IN_INCH"
     write(*,"(A)") "-height HEIGHT_IN_INCH"
     write(*,"(A)") "-colortable [Rainbow|Planck]"
     write(*,"(A)") "-imask [INTENSITY_MASK_FILE] (automatically chosen when mask = '')"
     write(*,"(A)") "-polmask [POL_MASK_FILE] (automatically chosen when mask = '')"
     write(*,"(A)") "-randrot [T|F]"     
     write(*,"(A)") "-min MIN_VALUE_FOR_MAP1"
     write(*,"(A)") "-max MAX_VALUE_FOR_MAP1"                    
     write(*,"(A)") "-min2 MIN_VALUE_FOR_MAP2"
     write(*,"(A)") "-max2 MAX_VALUE_FOR_MAP2"
     write(*,"(A)") "-want_caption [T|F]"
     write(*,"(A)") "-want_label [T|F]"
     write(*,"(A)") "-want_arrow [T|F]"
     write(*,"(A)") "-fft [F|T]"
     write(*,"(A)") "-want_pdf [F|T] ##want pdf output"     
     write(*,"(A)") "-norm_power [0]   ##normalize the image by T_center^norm_power"     
     write(*,"(A)") "-norm_to_corr [F/T] ##normalize the weight such that the expected radial profile is C(theta)"
     write(*,"(A)") "----------------------------------------------------------"     
     stop
  elseif(iargc().eq.1)then
     call coop_get_Input(1, params_file)
     call coop_do_general_stack(params_file)
  else
     call coop_get_command_line_argument(key = 'norm_power', arg = norm_power, default = 0.d0)
     call coop_get_command_line_argument(key = 'map', arg = map_file)
     call coop_get_command_line_argument(key = 'peaks', arg = peak_file)
     call coop_get_command_line_argument(key = 'field', arg = field_name)  
     call coop_get_command_line_argument(key = 'mask', arg = mask_file, default = "NONE")
     call coop_get_command_line_argument(key = 'randrot', arg = randrot, default = .true.)
     call coop_get_command_line_argument(key = 'norm_to_corr', arg = norm_to_corr, default = .false.)
     call coop_get_command_line_argument(key = 'want_pdf', arg = want_pdf, default = .false.)  
     call coop_get_command_line_argument(key = 'min', arg = zmin1, default=1.d31)
     call coop_get_command_line_argument(key = 'max', arg = zmax1, default=-1.d31)  
     call coop_get_command_line_argument(key = 'min2', arg = zmin2, default=1.d31)
     call coop_get_command_line_argument(key = 'max2', arg = zmax2, default=-1.d31)
     call coop_get_command_line_argument(key = 'fft', arg = coop_healpix_patch_stack_fft, default = .false.)

     call coop_get_command_line_argument(key = 'radius', arg = r_degree, default = 2.d0)
     call coop_get_command_line_argument(key = 'res', arg  = n, default = 30)

     dr = 2.d0*sin(r_degree*coop_SI_degree/2.d0)/n  
     if(randrot)then
        call coop_get_command_line_argument(key = 'out', arg = output, default = "stacked/"//trim(field_name)//"_on_"//trim(coop_file_name_of(peak_file, want_ext = .false.))//"_randRot")
     else
        call coop_get_command_line_argument(key = 'out', arg = output, default = "stacked/"//trim(field_name)//"_on_"//trim(coop_file_name_of(peak_file, want_ext = .false.))//"_NSalign")     
     endif
     call coop_get_command_line_argument(key = 'want_caption', arg = coop_healpix_patch_default_want_caption, default =  .true.)

     call coop_get_command_line_argument(key = 'want_label',  arg = coop_healpix_patch_default_want_label, default  = .true.)
     call coop_get_command_line_argument(key = 'want_arrow', arg = coop_healpix_patch_default_want_arrow, default = .true.)
     call coop_get_command_line_argument(key = 'width', arg = coop_healpix_patch_default_figure_width, default = 5.)
     call coop_get_command_line_argument(key = 'height', arg = coop_healpix_patch_default_figure_height, default = 4.2)
     call coop_get_command_line_argument(key = 'imask', arg = imask_file, default = "")
     call coop_get_command_line_argument(key = 'polmask', arg = polmask_file, default = "")  

     call sto%import(peak_file)
     sto%no_randrot = .not. randrot
     sto%norm_power = norm_power
     sto%norm_to_corr = norm_to_corr
     call hgm%read(map_file)
     call patch%init(field_name, n, dr)
     if(trim(mask_file) .ne. "NONE")then
        if(trim(mask_file) .ne. "")then
           call mask%read(mask_file, nmaps_wanted = 1)
        elseif(patch%tbs%mask_int .and. .not. patch%tbs%mask_pol)then
           call mask%read(imask_file, nmaps_wanted = 1)
        elseif(patch%tbs%mask_pol .and. .not. patch%tbs%mask_int)then
           call mask%read(polmask_file, nmaps_wanted = 1)
        else
           stop "For unclassified stacking maps you have to specify the mask explicitly"
        endif
        call hgm%apply_mask(mask = mask, remove_monopole = remove_mono)
     endif
     tmax = maxval(hgm%map(:,1))
     print*, "stacking on "//COOP_STR_OF(sto%peak_pix%n)//" points"  
     if(trim(mask_file).ne."NONE")then
        call hgm%stack_on_peaks(sto, patch, mask)
     else
        call hgm%stack_on_peaks(sto, patch)
     endif

     patch%caption = "stacked on "//COOP_STR_OF(patch%nstack_raw)//" "//trim(sto%caption)
     call coop_get_command_line_argument(key = 'colortable', arg = patch%color_table, default = 'Rainbow')
     select case(patch%nmaps)
     case(1)
        patch%tbs%zmin(1) = zmin1
        patch%tbs%zmax(1) = zmax1     
        call patch%plot(1, trim(adjustl(output))//".txt")
        if(want_pdf)call system("../utils/fasy.sh "//trim(adjustl(output))//".txt")
        write(*,*) "stacked COOP figure file saved in "//trim(adjustl(output))//".txt"        
        call coop_fits_file_write_image_2d(patch%image(:,:,1), trim(adjustl(output))//".fits")
        write(*,*) "stacked image data saved in "//trim(adjustl(output))//".fits"
     case default
        patch%tbs%zmin(1) = zmin1
        patch%tbs%zmax(1) = zmax1
        patch%tbs%zmin(2) = zmin2          
        patch%tbs%zmax(2) = zmax2          
        do i=1, patch%nmaps
           call patch%plot(i, trim(adjustl(output))//"_"//COOP_STR_OF(i)//".txt")
           write(*,*) "stacked COOP figure file saved in "//trim(adjustl(output))//"_"//COOP_STR_OF(i)//".txt"
        
           if(want_pdf)call system("../utils/fasy.sh "//trim(adjustl(output))//"_"//COOP_STR_OF(i)//".txt")
           call coop_fits_file_write_image_2d(patch%image(:,:,i), trim(adjustl(output))//"_"//COOP_STR_OF(i)//".fits")
           write(*,*) "stacked image data saved in "//trim(adjustl(output))//"_"//COOP_STR_OF(i)//".fits"           
                     
        enddo
     end select
     call patch%export(trim(adjustl(output))//".patch")
     call patch%get_all_radial_profiles()
     select case(patch%nmaps)
     case(1)
        do m = 0, patch%mmax, 2
           call fig%open(trim(adjustl(output))//"_m"//COOP_STR_OF(m)//".txt")
           call fig%init(xlabel="$r$", ylabel="radial profile")
           call coop_asy_curve(fig, patch%r, patch%fr(:, m/2, 1))
           call fig%close()
           call fig%open(trim(adjustl(output))//"_m"//COOP_STR_OF(m)//".dat")
           do i=0, patch%n
              write(fig%unit, "(2E14.5)") patch%r(i), patch%fr(i, m/2, 1)
           enddo
           call fig%close()        
        enddo
     case(2)
        do m = 0, patch%mmax, 2
           call fig%open(trim(adjustl(output))//"_m"//COOP_STR_OF(m)//".txt")
           call fig%init(xlabel="$r$", ylabel="radial profile")
           if(m.ne.0)then
              call coop_asy_curve(fig, patch%r, (patch%fr(:, m/2, 1)+patch%fr(:, m/2, 2))/2.d0)
           else
              call coop_asy_curve(fig, patch%r, patch%fr(:, m/2, 1) )
           endif
           call fig%close()
           call fig%open(trim(adjustl(output))//"_m"//COOP_STR_OF(m)//".dat")
           do i=0, patch%n
              write(fig%unit, "(3E14.5)") patch%r(i), patch%fr(i, m/2, :)
           enddo
           call fig%close()        
        enddo
     end select
  endif
#else
  print*, "You need to install healpix"
#endif  
end program Stacking_Maps
