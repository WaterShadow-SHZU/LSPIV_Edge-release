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
!
!     modif par BM 23-02-2015 : - bathy_p.dat est ecrit dans outputs.dir
!     modif par JLC 18-11-2016 : skip 3 lines more in PIV_param.dat (new format)
!     modif by JLC 02-03-2018 : read and write surface velocity coefficients, correction of transect interpolation
!     modif by JLC 19-06-2019 : extend float formats to allow for geographical coordinates (f10.3 replaced by f12.3)

program bathy_compute

   use lspiv_parameter
   use mod_bathy_compute, only: sub_bathy_compute

   implicit none

   character(len=160) :: workdir

   workdir = './'//outputs_dir//'/'

   call sub_bathy_compute(workdir)

end program bathy_compute
