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

program Q_compute

!     Modifications JLC decembre 2008
!     Moyenne IDW des 3 (au plus) plus proches vitesses
!     JLC, 25 June 2014: add loop for multi-section gauging
!     JLC, 18 October 2016: add measured Q and measured/total Q ratio
!     JLC, 14 December 2016: modified to take new PIV_param.dat format
!     JLC, 2  March 2018: modified for ellipsoid search areas (rx, ry radii)
!     JLC, 2  March 2018: account for surface velocity coefficients at each transect node

   use iso_fortran_env, only: error_unit, output_unit
   use errors, only: ERR_NO_ARGUMENT_1, ERR_NO_ARGUMENT_2
   use lspiv_parameter
   use mod_Q_compute, only: sub_Q_compute

#ifdef version_station
   integer :: n
   character (len=:), allocatable :: param1, param2, dir1, dir2

   call get_command_argument(1,param1)
   if (len_trim(param1) == 0) then
      write(error_unit,'(a)') ' >>>> ERREUR : il faut fournir 2 arguments'
      stop ERR_NO_ARGUMENT_1
   endif
   call get_command_argument(2,param2)
   if (len_trim(param2) == 0) then
      write(error_unit,'(a)') ' >>>> ERREUR : il faut fournir un 2e argument'
      stop ERR_NO_ARGUMENT_2
   endif

   n = len_trim(param1)
   if (param1(n:n) /= '/') then
      allocate (character(len=n+1) :: dir1)
      dir1 = trim(param1)//'/'
   else
      allocate (character(len=n) :: dir1)
      dir1 = trim(param1)
   endif
   n = len_trim(param2)
   if (param2(n:n) /= '/') then
      allocate (character(len=n+1) :: dir2)
      dir2 = trim(param2)//'/'
   else
      allocate (character(len=n) :: dir2)
      dir2 = trim(param2)
   endif
   call sub_Q_compute(dir1,dir2)
#endif /* version_station */

#ifndef version_station
   character(len=2) :: workdir
   workdir = './'
   call sub_Q_compute(workdir)
#endif /* version_station */

end program Q_compute
