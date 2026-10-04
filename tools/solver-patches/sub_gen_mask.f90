!! This file is part of Image_Velocimetry_Solver, a fortran solver for image velocimetry.
!!
!! Copyright (C) 2022 INRAE
!!
!! Image_Velocimetry_Solver is free software; you can redistribute it and/or
!! modify it under the terms of the GNU Lesser General Public
!! License as published by the Free Software Foundation; either
!! version 3 of the License, or (at your option) any later version.
!!
!! Alternatively, you can redistribute it and/or
!! modify it under the terms of the GNU General Public License as
!! published by the Free Software Foundation; either version 2 of
!! the License, or (at your option) any later version.
!!
!! Image_Velocimetry_Solver is distributed in the hope that it will be useful, but
!! WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
!! FITNESS FOR A PARTICULAR PURPOSE. See the GNU Lesser General Public License
!! or the GNU General Public License for more details.
!!
!! You should have received a copy of the GNU Lesser General Public
!! License and a copy of the GNU General Public License along with
!! Image_Velocimetry_Solver If not, see <http://www.gnu.org/licenses/>.

module mod_gen_mask

   contains

subroutine sub_gen_mask(workdir)
! generate mask.dat from flow area
   use iso_fortran_env, only: output_unit
   use lspiv_parameter, only: dp, outputs_dir, img_transf, img_pgm, read_img_ref,&
                      & flow_area, point2D, is_inside, point2D, run_external_program
   implicit none
   ! -- prototype --
   character (len=*), intent(in) :: workdir !working directory
   ! -- local variables --
   character (len=:), allocatable :: command
   character (len=14) :: script = 'mask.gnu'
   integer :: lw, nb, i, j, ni, nj, istop, ni0, nj0
   type (point2D), allocatable :: p(:)
   type (point2D) :: xy
   real(kind=dp) :: xmin, ymin, xmax, ymax, r

   write(output_unit,'(a)') '---> Generating mask.dat'
!    call write_progression(workdir,'Step 2 -- Computing flow area')

   !open and read flow area file
   open(newunit=lw,file=trim(workdir)//'/'//outputs_dir//'/'//flow_area,status='old')
   read(lw,*) Nb
   allocate(p(Nb+1))  !Nb+1 is necessary in case the polygon is not closed and we have to add a point
   i = 1
   read(lw,*) ni, nj  !width - height
   p(i) = point2D(x=real(ni,kind=dp),y=real(nj,kind=dp))
   ni0 = ni  ;  nj0 = nj
   do i = 2, Nb
      read(lw,*) ni, nj
      p(i) = point2D(x=real(ni,kind=dp),y=real(nj,kind=dp))
   enddo
   if (ni /= ni0 .or. nj /= nj0) then
      !adding one point to close the polygon
      Nb = Nb+1
      p(Nb) = p(1)
   endif
   rewind(lw)
   write(lw,'(i0)') Nb
   do i = 1, Nb-1
      write(lw,'(i0,1x,i0,1x,a,i0)') int(p(i)%x), int(p(i)%y), 'P', i
   enddo
   write(lw,'(i0,1x,i0,1x,a)') int(p(1)%x), int(p(1)%y), 'P1'
   close(lw)

   !image size
   call read_img_ref(trim(workdir)//'/'//outputs_dir,xmin, ymin, xmax, ymax, r, ni, nj)

   !generate the mask
   open(newunit=lw,file=trim(workdir)//'/'//outputs_dir//'/'//'mask.dat',form='formatted',status='new')
   do j = 1, nj
      xy%y = real(j-1,kind=dp)
      do i = 1, ni
         xy%x = real(i-1,kind=dp)
         if (is_inside(xy,p,nb)) write(lw,'(i0,1x,i0)') j,i
      enddo
   enddo
   close (lw)

   !generate a control image which show the first raw image, the polygon and the mask
   write(output_unit,'(a)')'---> Generating the control image'

   open(newunit=lw,file=trim(workdir)//'/'//outputs_dir//'/'//script,form='formatted',status='new')
   write(lw,'(a)') 'reset'
   write(lw,'(a,i0,a1,i0)') 'set term png size ',ni,',',nj
   write(lw,'(3a)') 'set output "flow_area_control.png"'
   write(lw,'(a)') 'set multiplot'
   !As the background picture's size is nj x ni, we choose xrange and yrange of these values
   write(lw,'(a,i0,a1)') 'set xrange [0:',ni-1,']'
   write(lw,'(a,i0,a1)') 'set yrange [0:',nj-1,']'
   write(lw,'(a)') 'unset tics'
   write(lw,'(a)') 'unset border'
   !Plot the background image
   write(lw,'(a)') 'plot "image.png" binary filetype=png with rgbimage'
   !Plot the mask
   write(lw,'(a,i0,a1)') 'set xrange [0:',ni-1,']'
   write(lw,'(a,i0,a)') 'set yrange [',nj-1,':0]'
   write(lw,'(a)') 'plot "mask.dat" using 2:1 notitle lc rgb "red"'
   !Plot the polygon
   write(lw,'(3a)') 'plot "',flow_area,'" using 1:2 notitle with lines lw 3 lc rgb "green"'
   write(lw,'(3a)') 'plot "',flow_area,'" using 1:2:3 notitle with labels point offset character 1, character 0.5 tc rgb "green"'
   write(lw,'(a)') 'unset multiplot'
   close(lw)

   allocate(character(len=2*len_trim(workdir)+len_trim(img_pgm)+len_trim(outputs_dir)+43) :: command)
   ! conversion image0001_transf.pgm into image.png
   write(command,'(2a,1x,a)') 'convert ',trim(workdir)//'/'//img_pgm//'/'//'image0001.pgm', &
                                   trim(workdir)//'/'//outputs_dir//'/'//'image.png'
   istop = 0 ; call run_external_program(command,.true.,istop)
   ! run gnuplot script
   write(command,'(4a)') 'cd ',trim(workdir)//'/'//outputs_dir,' && gnuplot ',script
   istop = 0 ; call run_external_program(command,.true.,istop)
   ! remove temporary files
   write(command,'(a)') 'rm '//trim(workdir)//'/'//outputs_dir//'/'//'image.png'
   istop = 0 ; call run_external_program(command,.true.,istop)
   write(command,'(a)') 'rm '//trim(workdir)//'/'//outputs_dir//'/'//script
   istop = 0 ; call run_external_program(command,.true.,istop)
end subroutine sub_gen_mask

end module mod_gen_mask
