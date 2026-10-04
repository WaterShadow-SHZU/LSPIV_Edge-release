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

! Program moy_ec

program moy_ec

!     modif par BM 23-02-2015 : - Changement du format de sortie pour etre sur que chaque
!                                 valeur soit séparée par au moins un blanc.
!     modif par JBF 27-02-2015 : utilisation de iostat_end pour tester proprement
!                                l'arrêt de lecture des fichiers

   use iso_fortran_env, only: error_unit, output_unit
   use lspiv_parameter
   use errors, only: ERR_NO_ARGUMENT_1, ERR_NO_ARGUMENT_2
   use lspiv_parameter
   use mod_moy_ec, only: sub_moy_ec

   implicit none

   character(len=:), allocatable :: dir1, dir2, dir3

#ifdef version_station
   integer :: n
   character (len=:), allocatable :: param1, param2

!    include "errors.i"

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
      allocate (character(len=n+5) :: dir2)
      dir2 = trim(param2)//'/out/'
      allocate (character(len=n+12) :: dir3)
      dir3 = trim(param2)//'/vel_filter/'
   else
      allocate (character(len=n+4) :: dir2)
      dir2 = trim(param2)//'out/'
      allocate (character(len=n+11) :: dir3)
      dir3 = trim(param2)//'vel_filter/'
   endif
#endif /* version_station */

#ifndef version_station
   allocate (character(len=14) :: dir1, dir2)
   allocate (character(len=13) :: dir3)
   dir1 = './outputs.dir/'
   dir2 = './outputs.dir/'
   dir3 = './vel_filter/'
#endif /* version_station */

   call sub_moy_ec(dir1, dir2, dir3)

end program moy_ec
