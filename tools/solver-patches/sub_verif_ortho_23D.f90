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

module mod_verif_ortho

   contains

subroutine sub_verif_ortho(workdir)

!     check 3D ortho-rectification parameters by computing the orthorectified space coordinates (Xt,Yt) of the GRPs from their image coordinates (i,j) and vertical space coordinate (Z)
!    modif du 1-06-2011 MJ pour prise en compte des orthorectification 2d ou 3d


!     The input file GRP.dat should be formated as:
!     - 3 lines of header:
!         - The title: "GRP"
!         - The number of GRPs used; for example: "7". At least 6 GRPs are required.
!         - The label of the columns: "X  Y  Z  i  j"
!     - The GRPs coordinates: Space coordinates and image coordinates

!      The input file coeff.dat is produced by solver "ortho" it should be formated as :
!     - nb of coefficients si nb=8 transfo 2d (8 coeff) si nb=11 transfo 3d (11 coeff)
!    - values of coefficients

!      The output file GRP_test_ortho.dat will be formated as:
!     - 3 lines of header:
!         - The title: "GRP"
!         - The number of GRPs used; for example: "7". At least 6 GRPs are required.
!         - The label of the columns: "X  Y  Z  i  j  Xt  Yt  Dev"
!     - The GRPs coordinates: Space coordinates and image coordinates
   use iso_fortran_env, only: error_unit
   use errors, only: ERR_COMPUTING_COEF
   use lspiv_parameter, only: dp, coeff_dat, grp
   implicit none
   ! protype
   character (len=*), intent(in) :: workdir !working directory

   integer :: Nb  !number of GRPs
   integer :: nbc  ! number of coefficients
   integer :: i
   integer,allocatable :: x(:), y(:)
   real(kind=dp),allocatable :: xp(:), yp(:), zp(:)
   real(kind=dp),allocatable :: xt(:), yt(:), dev(:)
   real(kind=dp),allocatable :: m1(:), m2(:), m3(:)
   real(kind=dp),allocatable :: p1(:), p2(:), p3(:)
   real(kind=dp),allocatable :: q1(:), q2(:), q3(:)
   real(kind=dp) :: a1,a2,a3,a4,b1,b2,b3,b4,c1,c2,c3
   real(kind=dp) :: a(8)
   integer :: lu, lw

   !open and read GRP file GRP.dat !!! REPRENDRE MODIF ORTHO JLC !!!
   open(newunit=lu,file=trim(workdir)//'/'//GRP,status='old')
   read(lu,*)
   read(lu,*) Nb
   read(lu,*)

   allocate(x(Nb),y(Nb))
   allocate(xp(Nb),yp(Nb),zp(Nb))
   allocate(xt(Nb),yt(Nb),dev(Nb))
   allocate(m1(Nb),m2(Nb),m3(Nb))
   allocate(p1(Nb),p2(Nb),p3(Nb))
   allocate(q1(Nb),q2(Nb),q3(Nb))

   do i = 1, Nb
      read(lu,*) xp(i), yp(i), zp(i), x(i), y(i)
   enddo
   close(lu)

   !open and read 3D or 2D ortho-rectification parameters in file coeff.dat
   !si nb=8 transfo 2d (8 coeff) si nb=11 transfo 3d (11 coeff)
   open(newunit=lu,file=trim(workdir)//'/'//coeff_dat,status='old')
   open(newunit=lw,file=trim(workdir)//'/'//'GRP_test_ortho.dat',status='unknown')

   read(lu,*) nbc

   if (nbc == 8) then
      do i = 1, nbc
         read(lu,*) a(i)
      enddo

!     compute the orthorectified position Xt,Yt and position error dev for each GRP
      do i = 1, Nb
         xt(i) = (a(1)*x(i)+a(2)*y(i)+a(3))/(a(7)*x(i)+a(8)*y(i)+1._dp)
         yt(i) = (a(4)*x(i)+a(5)*y(i)+a(6))/(a(7)*x(i)+a(8)*y(i)+1._dp)
         dev(i)= sqrt((xt(i)-xp(i))*(xt(i)-xp(i)) + (yt(i)-yp(i))*(yt(i)-yp(i)))
      enddo

!     write the results in the output file GRP_test_ortho.dat
      write(lw,*) 'GRP verification of 2D ortho-rectification'
      write(lw,*) Nb
      write(lw,*) 'X  Y  Z  i  j  Xt  Yt  Dev'
      do i = 1, Nb
         write(lw,*) xp(i),yp(i),zp(i),x(i),y(i),xt(i),yt(i),dev(i)
      enddo

   elseif (nbc == 11) then
      read(lu,*) a1  ;  read(lu,*) a2  ;  read(lu,*) a3  ;  read(lu,*) a4
      read(lu,*) c1  ;  read(lu,*) c2  ;  read(lu,*) c3
      read(lu,*) b1  ;  read(lu,*) b2  ;  read(lu,*) b3  ;  read(lu,*) b4
!     compute inverse transformation coefficients m, p, q for each GRP
      do i = 1, Nb
         m1(i) =   zp(i)*(b2*c3-b3*c2)+(b2-b4*c2)
         m2(i) = -(zp(i)*(a2*c3-a3*c2)+(a2-a4*c2))
         m3(i) =   zp(i)*(a2*b3-a3*b2)+(a2*b4-a4*b2)
         p1(i) =   b1*c2-b2*c1
         p2(i) = -(a1*c2-a2*c1)
         p3(i) =   a1*b2-a2*b1
         q1(i) = -(zp(i)*(b1*c3-b3*c1)+(b1-b4*c1))
         q2(i) =   zp(i)*(a1*c3-a3*c1)+(a1-a4*c1)
         q3(i) = -(zp(i)*(a1*b3-a3*b1)+(a1*b4-a4*b1))
      enddo

      !compute the orthorectified position Xt,Yt and position error dev for each GRP
      do i = 1, Nb
         xt(i) = (m1(i)*x(i)+m2(i)*y(i)+m3(i)) / (p1(i)*x(i)+p2(i)*y(i)+p3(i))
         yt(i) = (q1(i)*x(i)+q2(i)*y(i)+q3(i)) / (p1(i)*x(i)+p2(i)*y(i)+p3(i))
         dev(i) = sqrt( (xt(i)-xp(i))*(xt(i)-xp(i)) + (yt(i)-yp(i))*(yt(i)-yp(i)) )
      enddo

      !write the results in the output file GRP_test_ortho.dat
      write(lw,*) 'GRP verification of 3D ortho-rectification'
      write(lw,*) Nb
      write(lw,*) 'X  Y  Z  i  j  Xt  Yt  Dev'
      do i = 1, Nb
         write(lw,*) xp(i),yp(i),zp(i),x(i),y(i),xt(i),yt(i),dev(i)
      enddo
   else
      write(error_unit,'(a)') '>>>> Erreur : le nombre de coefficients doit être 8 ou 11'
      stop ERR_COMPUTING_COEF
   endif
   close (lu)
   close (lw)

end subroutine sub_verif_ortho

end module mod_verif_ortho
