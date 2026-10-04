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

program PIV

!     PIV analysis of a sequence of images, using CDWS with sub-pixel
!     gaussian fit.
   use iso_fortran_env, only: error_unit, output_unit
   use lspiv_parameter
#ifdef openmp
   use omp_lib
#endif /* openmp */
   use mod_PIV, only: sub_PIV
   implicit none

   character (len=160) :: dir1, dir2
   character (len=:), allocatable :: img1, img2, piv_dat, param_file, grid_file
   integer :: Bi, Bj, Sim, Sjm, Sip, Sjp, ni, nj
   real(kind=dp) :: R_min, R_max
   integer :: compt, ncore, iarg = 0
   integer, allocatable :: x(:), y(:)
   logical :: silent = .true.
#ifdef openmp
   character (len=2) param3
#endif /* openmp */

   iarg = 0 !to read param3 as first argument if not version_station
#ifdef version_station
   iarg = iarg+1 ; call get_command_argument(1,dir1)
   iarg = iarg+1 ; call get_command_argument(2,dir2)
#endif /* version_station */

#ifndef version_station
   dir1 = './'//outputs_dir
   dir2 = '.'
#endif /* version_station */

   ncore = 1  !value if sequential version
#ifdef openmp
   iarg = iarg+1 ; call get_command_argument(iarg,param3)
   read(param3,'(i2)') ncore
#endif /* openmp */

   !read the PIV parameters data file
   allocate(character(len=len_trim(dir1)+len_trim(PIV_param)+1) :: param_file)
   param_file = trim(dir1)//'/'//PIV_param
   ! NOTE: set silent to .true. to tell lire_PIV_param() not to write on standard output or standard error
   call lire_PIV_param(param_file, Bi, Bj, Sim, Sjm, Sip, Sjp, R_min, R_max, ni, nj, silent)

   allocate(character(len=len_trim(dir1)+len_trim(grid)+1) :: grid_file)
   grid_file = trim(dir1)//'/'//grid
   call lire_Grid(grid_file, compt, x, y)

   allocate(character(len=len_trim(dir2)+len_trim(img_transf)+19) :: img1, img2)
   img1    = trim(dir2)//'/'//img_transf//'/image1_transf.pgm'
   img2    = trim(dir2)//'/'//img_transf//'/image2_transf.pgm'
   allocate(character(len=len_trim(dir2)+len_trim(vel_raw)+9) :: piv_dat)
   piv_dat = trim(dir2)//'/'//vel_raw//'/piv.dat'

   call sub_PIV(img1, img2, piv_dat, Bi, Bj, Sim, Sjm, Sip, Sjp, R_min, R_max, ni, nj, compt, x, y, ncore)

   deallocate (param_file, grid_file, img1, img2, piv_dat, x, y)

end program PIV
