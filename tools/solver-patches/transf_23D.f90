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

! ---------------------------
! LSPIV-solvers, V1.0, 2014
!
! Jerome Le Coz & Jean-Baptiste Faure, Irstea
!
! Contributions:
! -------------
! LSPIV-solvers was built on original developments from the PhD work of
! Alex Hauet (LTHE Grenoble, University of Iowa), following the seminal works
! on LSPIV by Ichiro Fujita and Marian Muste.
! Recent contributions by Alex Hauet (EDF) and Magali Jodeau (EDF) are also acknowledged.

program transf_img

   use lspiv_parameter
   use mod_transf_23D

!     From a raw pgm image, compute the ortho-rectified image using
!     the parameters of coeff.dat.
!     mj 4-05-2011 modifications for 2D or 3D ortho rectification
!     jlc 3-01-2017 transformation without ortho rectification and simplification of the code structure

   use iso_fortran_env, only: error_unit, output_unit
   use lspiv_parameter
#ifdef openmp
   use omp_lib
#endif /* openmp */
   use errors, only: ERR_ORTHORECTIFICATION_SERVER_FAILED
   implicit none


   character (len=160) :: dir1='./outputs.dir', dir2='.', coeff_file='coeff.dat'
   integer :: nb_arg = 0
   character(len=18) :: image
   real(kind=dp) :: xmin, xmax, ymin, ymax, r, a(11), h
   integer :: ni, nj, nb, istop, ncore, lh
   character(len=:), allocatable :: image_in, image_out
#ifdef openmp
   character (len=2) :: param3
#endif /* openmp */

#ifdef version_station
   nb_arg = nb_arg+1 ; call get_command_argument(nb_arg,dir1)
   nb_arg = nb_arg+1 ; call get_command_argument(nb_arg,dir2)
   coeff_file = 'coeff_plan.dat'
#endif /* version_station */

   ncore = 1  !value if sequential version
#ifdef openmp
   nb_arg = nb_arg+1 ; call get_command_argument(nb_arg,param3)
   read(param3,'(i2)') ncore
#endif /* openmp */

   call read_img_ref(dir1,xmin,ymin,xmax,ymax,r,nj,ni)
   call read_coeff_ortho(dir1,nb,a)

   allocate(character(len=len_trim(dir2)+len_trim(img_pgm)+12) :: image_in)
   image_in = trim(dir2)//'/'//img_pgm//'/image1.pgm'
   allocate(character(len=len_trim(dir2)+len_trim(img_transf)+19) :: image_out)
   image_out = trim(dir2)//'/'//img_transf//'/image1_transf.pgm'

   ! Use the P2/P5 auto-detecting reader: lspiv_batch.py writes P5 (binary)
   ! by default, and the upstream P2-only reader rejects it with istop=1,
   ! which surfaces as transf_a.exe exit code 24.
   read_PGM_P2 => read_pgm_any_transf
   if (nb == 8) then
      call sub_transf_img_2D(a,xmin,ymin,xmax,ymax,r,ni,nj,image_in,image_out,ncore,istop)
   elseif (nb == 11) then
      open(newunit=lh,file=trim(dir1)//'/'//h_dat,form='formatted',status='old')
      read(lh,*) h
      close (lh)
      call sub_transf_img_3D(a,h,xmin,ymin,xmax,ymax,r,ni,nj,image_in,image_out,ncore,istop)
   else
      call sub_transf_img_0(a,xmin,ymin,xmax,ymax,r,ni,nj,image_in,image_out,ncore,istop)
   endif

   if (istop /= 0) then
      write(error_unit,'(a,i0)') '>>>> ERROR : orthorectification solver failed with error code ',istop
      stop ERR_ORTHORECTIFICATION_SERVER_FAILED
   else
      deallocate (image_in, image_out)
   endif

end program transf_img
