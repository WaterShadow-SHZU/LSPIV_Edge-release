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

program ortho
!     compute the 3D ortho-rectification parameters from GRPs.
!     The file GRP.dat should be formated as:
!     - 3 lines of header:
!         - The title: "GRP"
!         - The number of GRPs used; for example: "7". At least 6 GRPs are required.
!         - The label of the columns: "X  Y  Z  i  j"
!     - The GRPs coordinates: Space coordinates and image coordinates

!    ajout MJ du 03-05-2011
!    calcul des coef transfo 2D si les z des GRP sont identiques
!    modified by JLC on 6 March 2018 to reduce the GRP coordinates (3D orthorectification only)

   use lspiv_parameter, only: outputs_dir
   use mod_ortho, only: sub_ortho

   implicit none

   call sub_ortho('./'//outputs_dir)

end program ortho
