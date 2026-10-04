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

module mod_ortho

   use lspiv_parameter, only: dp, coeff_dat, grp, point2D, is_equal_p2d, is_on_right_side, is_inside

   procedure (compute_XY_2D), pointer :: compute_XY => null()

   contains

subroutine sub_ortho(workdir)
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

   implicit none
   ! protype
   character (len=*), intent(in) :: workdir !working directory

   integer :: Nb  !number of GRPs
   integer :: i, a
   integer,allocatable :: x(:), y(:)

   real(kind=dp),allocatable :: T(:,:), Z(:,:), Tt(:,:), TtTTt(:,:), TtT(:,:), TZ(:,:)
   real(kind=dp),allocatable :: xp(:), yp(:), zp(:), TZtemp(:,:)
   real(kind=dp) :: Dx, Dy, Dz, beta

   integer :: lw

   a = 1
   !open and read GRP file GRP.dat
   open(newunit=lw,file=trim(workdir)//'/'//GRP,status='old')
   read(lw,*)
   read(lw,*) Nb
   read(lw,*)

   allocate(x(Nb),y(Nb),xp(Nb),yp(Nb),zp(Nb))

   do i=1,Nb
      read(lw,*)xp(i),yp(i),zp(i),x(i),y(i)
   enddo
   close(lw)

   !condition pour ortho 2d ou 3d
   do i=2,Nb
      if ( abs(zp(1)-zp(i)) .le. 0.00001_dp) then
         a = a+1
      endif
   enddo

   ! a = Nb si tous les zGRP sont identiques -> transfo 2D -----------------------------------------------------------------
   if (a .eq. Nb) then
      allocate(T(2*Nb,8),Z(2*Nb,1),Tt(8,2*Nb),TtTTt(8,2*Nb),TtT(8,8),TZ(8,1),TZtemp(8,1))
      !format the data onto the matrix T
      do i = 1, Nb
         T(i,1) = real(x(i),kind=dp)
         T(i,2) = real(y(i),kind=dp)
         T(i,3) = 1._dp
         T(i,4) = real(-x(i),kind=dp)*xp(i)
         T(i,5) = real(-y(i),kind=dp)*xp(i)
         T(i,6) = 0._dp
         T(i,7) = 0._dp
         T(i,8) = 0._dp
      enddo
      do i = Nb+1, 2*Nb
         T(i,1) = 0._dp
         T(i,2) = 0._dp
         T(i,3) = 0._dp
         T(i,4) = real(-x(i-Nb),kind=dp)*yp(i-Nb)
         T(i,5) = real(-y(i-Nb),kind=dp)*yp(i-Nb)
         T(i,6) = real(x(i-Nb),kind=dp)
         T(i,7) = real(y(i-Nb),kind=dp)
         T(i,8) = 1._dp
      enddo
      !format the data onto the matrix Z
      do i = 1, Nb
         Z(i,1) = real(xp(i),kind=dp)
      enddo
      do i = Nb+1, 2*Nb
         Z(i,1) = real(yp(i-Nb),kind=dp)
      enddo

      !compute Tt, transposed matrix of T
      call trans(T,Tt,2*Nb,8)
      !multiply Tt with T
      call mmult(Tt,T,TtT,8,2*Nb,8)
      !compute the inverse matrix of TtT
      call gaussj(TtT,8,8)
      !multiply the inverse matrix with Tt
      call mmult(TtT,Tt,TtTTt,8,8,2*Nb)
      !multiply TtTTt with Z to get TZ, the vector of parameters
      call mmult(TtTTt,Z,TZ,8,2*Nb,1)

      !write the results in the output file coeff.dat
      open(newunit=lw,file=trim(workdir)//'/'//coeff_dat,status='unknown')
         write(lw,*)8
         do i = 1, 3
            write(lw,*) TZ(i,1)
         enddo
         write(lw,*) TZ(6,1)
         write(lw,*) TZ(7,1)
         write(lw,*) TZ(8,1)
         write(lw,*) TZ(4,1)
         write(lw,*) TZ(5,1)
      close(lw)

   else
! calcul coeff 3D -----------------------------------------------------------------
      allocate(T(2*Nb,11),Z(2*Nb,1),Tt(11,2*Nb),TtTTt(11,2*Nb),TtT(11,11),TZ(11,1),TZtemp(11,1))

      !reduce the GRP coordinates
      Dx = -minval(xp) !-sum(xp)/Nb
      Dy = -minval(yp) !-sum(yp)/Nb
      Dz = -minval(zp) !-sum(zp)/Nb
      do i = 1, Nb
      xp(i) = xp(i) + Dx
      yp(i) = yp(i) + Dy
      zp(i) = zp(i) + Dz
      !write(*,'(3f10.3)') xp(i),yp(i),zp(i)
      enddo

      !format the data onto the matrix T
      do i = 1, Nb
         T(i,1) = xp(i)
         T(i,2) = yp(i)
         T(i,3) = zp(i)
         T(i,4) = 1._dp
         T(i,5) = real(-x(i),kind=dp)*xp(i)
         T(i,6) = real(-x(i),kind=dp)*yp(i)
         T(i,7) = real(-x(i),kind=dp)*zp(i)
         T(i,8) = 0._dp
         T(i,9) = 0._dp
         T(i,10) = 0._dp
         T(i,11) = 0._dp
      enddo
      do i = Nb+1,2*Nb
         T(i,1) = 0._dp
         T(i,2) = 0._dp
         T(i,3) = 0._dp
         T(i,4) = 0._dp
         T(i,5) = real(-y(i-Nb),kind=dp)*xp(i-Nb)
         T(i,6) = real(-y(i-Nb),kind=dp)*yp(i-Nb)
         T(i,7) = real(-y(i-Nb),kind=dp)*zp(i-Nb)
         T(i,8) = xp(i-Nb)
         T(i,9) = yp(i-Nb)
         T(i,10) = zp(i-Nb)
         T(i,11) = 1._dp
      enddo

      !format the data onto the matrix Z
      do i = 1, Nb
         Z(i,1) = real(x(i),kind=dp)
      enddo
      do i = Nb+1, 2*Nb
         Z(i,1) = real(y(i-Nb),kind=dp)
      enddo

      !compute Tt, transposed matrix of T
      call trans(T,Tt,2*Nb,11)
      !multiply Tt with T
      call mmult(Tt,T,TtT,11,2*Nb,11)
      !compute the inverse matrix of TtT
      call gaussj(TtT,11,11)
      !multiply the inverse matrix with Tt
      call mmult(TtT,Tt,TtTTt,11,11,2*Nb)
      !multiply TtTTt with Z to get TZ, the vector of parameters
      call mmult(TtTTt,Z,TZ,11,2*Nb,1)

      !compute orthorectification coefficients for NON reduced coordinates
         ! store coefficients computed for reduced GRP coordinates in TZtemp
         do i = 1, 11
            TZtemp(i,1) = TZ(i,1)
         enddo

         beta = TZtemp(5,1)*Dx + TZtemp(6,1)*Dy + TZtemp(7,1)*Dz + 1
         do i = 1, 3
            TZ(i,1) = TZtemp(i,1) / beta
         enddo
         TZ(4,1) = (TZtemp(4,1)+TZtemp(1,1)*Dx+TZtemp(2,1)*Dy+TZtemp(3,1)*Dz)/beta
         do i = 5, 10
            TZ(i,1) = TZtemp(i,1) / beta
         enddo
         TZ(11,1) = (TZtemp(11,1)+TZtemp(8,1)*Dx+TZtemp(9,1)*Dy+TZtemp(10,1)*Dz)/beta

      !write the results in the output file coeff.dat
      open(newunit=lw,file=trim(workdir)//'/'//coeff_dat,status='unknown')
         write(lw,*) 11
         do i = 1, 11
            write(lw,*) TZ(i,1)
         enddo
      close(lw)
   endif
end subroutine sub_ortho


subroutine trans(A,At,m,n)
!Transpose a matrix or vector A(m,n) onto At(n,m)
   implicit none
   integer :: i, j, m, n
   real(kind=dp) :: A(m,n), At(n,m)

   do i = 1, n
      do j = 1, m
         At(i,j) = A(j,i)
      enddo
   enddo
end subroutine trans


subroutine mmult(A,B,C,m,n,o)
!Multiplication of 2 matrix or vectors
!   A(m,n)xB(n,o)=C(m,o)
   implicit none
   integer :: i, j, k, m, n, o
   real(kind=dp) :: A(m,n), B(n,o), C(m,o), part

   do i = 1, m
      do j = 1, o
         C(i,j) = 0._dp
         do k = 1,n
            part = A(i,k)*B(k,j)
            C(i,j) = C(i,j)+part
         enddo
      enddo
   enddo
end subroutine mmult


subroutine gaussj(a,n,np)
   !Linear equation solution by Gauss-Jordan elimination, equation (2.1.1) above. a(1:n,1:n)
   !is an input matrix stored in an array of physical dimensions np by np. b(1:n,1:m) is an input
   !matrix containing the m right-hand side vectors, stored in an array of physical dimensions
   !np by mp. On output, a(1:n,1:n) is replaced by its matrix inverse, and b(1:n,1:m) is
   !replaced by the corresponding set of solution vectors.
   implicit none

   integer, parameter :: nmax=50
   !parameter: nmax is the largest anticipated value of n.
   integer :: n,np
   real(kind=dp) :: a(np,np)
   integer :: i,icol,irow,j,k,l,ll,indxc(nmax),indxr(nmax),ipiv(nmax)
   !the integer arrays ipiv, indxr, and indxc are used
   !for bookkeeping on the pivoting.
   real(kind=dp) :: big,dum,pivinv

   ipiv(1:n) = 0
   irow = -1  ;  icol = -1  !initialisation
   do i = 1, n
   !This is the main loop over the columns to be reduced.
      big = 0._dp
      do j = 1, n
      !This is the outer loop of the search for a pivot element.
         if(ipiv(j).ne.1)then
            do k = 1,n
               if (ipiv(k).eq.0) then
                  if (abs(a(j,k)).ge.big) then
                     big = abs(a(j,k))
                     irow = j
                     icol = k
                  endif
               endif
            enddo
         endif
      enddo
      ipiv(icol) = ipiv(icol)+1
      !We now have the pivot element, so we interchange rows, if needed, to put the pivot
      !element on the diagonal. The columns are not physically interchanged, only relabeled:
      !indxc(i), the column of the ith pivot element, is the ith column that is reduced, while
      !indxr(i) is the row in which that pivot element was originally located. If indxr(i)  =
      !indxc(i) there is an implied column interchange. With this form of bookkeeping, the
      !solution will end up in the correct order, and the inverse matrix will be scrambled
      !by columns.
      if (irow.ne.icol) then
         do l = 1,n
            dum = a(irow,l)
            a(irow,l) = a(icol,l)
            a(icol,l) = dum
         enddo
      endif
      indxr(i) = irow
      !We are now ready to divide the pivot row by the pivot
      !element, located at irow and icol.
      indxc(i) = icol
      if (abs(a(icol,icol)) < 1.e-20_dp) print *, 'singular matrix in gaussj'
      pivinv = 1./a(icol,icol)
      a(icol,icol) = 1._dp
      do l = 1,n
         a(icol,l) = a(icol,l)*pivinv
      enddo

      do ll = 1,n
         !Next, we reduce the rows...
         if(ll.ne.icol)then
            !...except for the pivot one, of course.
            dum = a(ll,icol)
            a(ll,icol) = 0._dp
            do l = 1,n
               a(ll,l) = a(ll,l)-a(icol,l)*dum
            enddo
         endif
      enddo
   enddo

   !This is the end of the main loop over columns of the reduction.
   do l = n,1,-1
      !It only remains to unscramble the solution in view
      !of the column interchanges. We do this by interchanging
      !pairs of columns in the reverse order
      !that the permutation was built up.
      if (indxr(l).ne.indxc(l)) then
         do k = 1, n
            dum = a(k,indxr(l))
            a(k,indxr(l)) = a(k,indxc(l))
            a(k,indxc(l)) = dum
         enddo
      endif
   enddo
end subroutine gaussj


function compute_XY_2D(ix,iy,a) result(q)
!Compute XY metric coordinates (q) from pixels coordinates (ix,iy) on the source image
!case 2D
   implicit none
   ! -- protype --
   integer, intent(in) :: ix, iy
   real(kind=dp), intent(in) :: a(*)
   type (point2D) :: q

   q%x = (a(1)*ix+a(2)*iy+a(3))/(a(7)*ix+a(8)*iy+1._dp)
   q%y = (a(4)*ix+a(5)*iy+a(6))/(a(7)*ix+a(8)*iy+1._dp)
end function compute_XY_2D


function compute_XY_3D(ix,iy,a) result(q)
!Compute XY metric coordinates (q) from pixels coordinates (ix,iy) on the source image
!case 2D
   implicit none
   ! -- protype --
   integer, intent(in) :: ix, iy
   real(kind=dp), intent(in) :: a(*)
   type (point2D) :: q

   !compute the orthorectified position Xt,Yt and position error dev for each GRP
   !q%x = (m1*ip%x+m2*ip%y+m3)/(p1*ip%x+p2*ip%y+p3)
   !q%y = (q1*ip%x+q2*ip%y+q3)/(p1*ip%x+p2*ip%y+p3)
   q%x = (a(1)*ix+a(2)*iy+a(3))/(a(4)*ix+a(5)*iy+a(6))
   q%y = (a(7)*ix+a(8)*iy+a(9))/(a(4)*ix+a(5)*iy+a(6))
end function compute_XY_3D


function ortho_rectif(p,a,resol) result(q)
!transformation des coordonnées image (x,y) sur l'image brute en coordonnées image (pixels) sur l'image orthorectifiée
   implicit none
   ! -- protype --
   type (point2D), intent(in) :: p
   real(kind=dp), intent(in) :: a(*), resol
   type (point2D) :: q

   q%x = aint((a(1)*p%x+a(2)*p%y+a(3))/(a(7)*p%x+a(8)*p%y+1._dp) / resol)
   q%y = aint((a(4)*p%x+a(5)*p%y+a(6))/(a(7)*p%x+a(8)*p%y+1._dp) / resol)
end function ortho_rectif


subroutine compute_A_coeff(coeff_file, a, nbc)
!compute the coefficients for functions compute_XY()
   use iso_fortran_env, only: error_unit, output_unit
   use lspiv_parameter, only: dp
   implicit none
   !-- prototype --
   character(len=*), intent(in) :: coeff_file
   real(kind=dp), intent(out) :: a(9)
   integer, intent(out) :: nbc
   !--local variables --
   logical :: bExist
   integer :: lu, ios, n
   real(kind=dp) :: a1, a2, a3, a4, c1, c2, c3, b1, b2, b3, b4
   real(kind=dp) :: m1, m2, m3, p1, p2 , p3, q1, q2, q3

   !read coeff.dat
   open(newunit=lu,file=trim(coeff_file),form='formatted',status='old')
   read(lu,*) nbc

   if (nbc == 8) then
      do n = 1, nbc
         read(lu,*) a(n)
      enddo
   elseif (nbc == 11) then
      read(lu,*) a1  ;  read(lu,*) a2  ;  read(lu,*) a3  ;  read(lu,*) a4
      read(lu,*) c1  ;  read(lu,*) c2  ;  read(lu,*) c3
      read(lu,*) b1  ;  read(lu,*) b2  ;  read(lu,*) b3  ;  read(lu,*) b4
!     compute inverse transformation coefficients m, p, q assuming zp = 0 (water level)
      m1 =  b2-b4*c2
      m2 = -(a2-a4*c2)
      m3 =  a2*b4-a4*b2
      p1 =  b1*c2-b2*c1
      p2 = -(a1*c2-a2*c1)
      p3 =  a1*b2-a2*b1
      q1 = -(b1-b4*c1)
      q2 =  a1-a4*c1
      q3 = -(a1*b4-a4*b1)

      a(1) = m1  ;  a(2) = m2  ;  a(3) = m3
      a(4) = p1  ;  a(5) = p2  ;  a(6) = p3
      a(7) = q1  ;  a(8) = q2  ;  a(9) = q3
   endif
   close(lu)
end subroutine compute_A_coeff


function estimated_resolution(GRP_dat,ni,nj,a)
!compute the resolution from the GRP
   implicit none
   ! -- prototype
   character(len=*), intent(in) :: GRP_dat
   integer, intent(in) :: ni, nj
   real(kind=dp), intent(in) :: a(*)
   real(kind=dp) :: estimated_resolution
   !--local variables --
   type(point2D), allocatable :: xy(:), p(:)
   integer, allocatable :: lp(:)
   real(kind=dp) :: x, y, z, area
   integer :: lu, n, ix, jy, nv, nb_points, num

   !reading GRP.dat
   open(newunit=lu,file=trim(GRP_dat),form='formatted',status='old')
   read(lu,*)
   read(lu,*) nb_points
   read(lu,*)
   allocate (xy(nb_points),lp(nb_points))
   do n = 1, nb_points
      read(lu,*) x, y, z, ix, jy
        xy(n) = point2D(x,y)
      xy(n) = compute_XY(ix,jy,a)
   enddo
   close (lu)

   !computing the convex hull using metric coordinate
   call jarvis(xy,nb_points,lp,nv)

   !computing area of convex hull enclosing the GRP
   allocate(p(nv+1))
   do n = 1, nv
      p(n) = xy(lp(n))
   enddo
   area = area_poly_convex(p,nv)

   !computing the amount of pixels inside de convex hull
   !closing the polygon
   nv = nv + 1
   p(nv) = p(1)
   num = number_interior_pixels(p,nv,ni,nj,a)

   estimated_resolution = sqrt(area/real(num,kind=dp))
end function estimated_resolution


function length(A,B)
!compute the length of the segment [A,B]
   implicit none
   !--prototype --
   type(point2D), intent(in) :: A, B
   real(kind=dp) :: length

   length = sqrt( (A%x-B%x)**2 + (A%y-B%y)**2)
end function length


function heron(A,B,C)
!compute the area of triangle (A,B,C) using Heron formula
   implicit none
   !--prototype --
   type(point2D), intent(in) :: A, B, C
   real(kind=dp) :: heron
   !--local variables --
   real(kind=dp) :: p, la, lb, lc
   !compute the length of each side
   la = length(B,C)  ;  lb = length(A,C)  ;  lc = length(A,B)

   p = 0.5_dp * (la + lb + lc)
   heron = sqrt(p*(p-la)*(p-lb)*(p-lc))
end function heron


function area_poly_convex(p,np)
!compute the area of the convex polygon given by p(:)
   implicit none
   !-- prototype --
   integer, intent(in) :: np
   type(point2D), intent(in) :: p(np)
   real(kind=dp) :: area_poly_convex
   !-- local variables --
   real(kind=dp) :: area
   integer :: k

   area_poly_convex = 0._dp
   do k = 2, np-1
      area_poly_convex = area_poly_convex + heron(p(1),p(k),p(k+1))
   enddo
end function area_poly_convex


function number_interior_pixels(p,np,ni,nj,a)
!compute the amount of pixels inside the convex polygon p
!we assume that p is closed : p(1) = p(np)
! ni, nj = size of the source image
! a = orthorectification coefficients
   implicit none
   !-- prototype --
   integer, intent(in) :: np, ni, nj
   type(point2D), intent(in) :: p(np)
   real(kind=dp), intent(in) :: a(*)
   integer :: number_interior_pixels
   !-- local variables --
   integer :: i, j, num
   type(point2D) :: q, iq

   num = 0

   do j = 1, nj     !row index <-> y coordinate
      do i = 1, ni  !column index <-> x coordinate
         q = compute_XY(i,j,a)
         if (is_inside(q,p,np)) num = num + 1
      enddo
   enddo
   number_interior_pixels = num
end function number_interior_pixels


subroutine jarvis(p,np,lp,nv)
!compute the convex envlop of {P(i), i=1,np}
!the result is the list of index in p of the vertices {lp(i), i=1,nv}
!the list lp starts with the vertex with minimal y-coordinate
   implicit none
   ! -- prototype --
   integer, intent(in) :: np
   type(point2D), intent(in) :: p(np)
   integer, intent(out) :: nv
   !type(point2D), intent(out) :: envlop(np)
   integer, intent(out) :: lp(np)  !indice dans la liste p(:)
   ! -- local variables --
   integer :: k, j, ka, kc
   real(kind=dp) :: ymin
   type(point2D) :: pc

   !step 1 : find the point p(i) with minimal y-coordinate
   !         this point is on the envlop and will be the starting point
   lp(1) = 1
   do k = 2, np
      if (p(k)%y < p(lp(1))%y) lp(1) = k
   enddo

   !step 2 : compute convex envlop
   kc = lp(1)  ;  nv = 1
   do j = 2, np
      !choose ka such that p(ka) =/= p(kc)
      do k = 1, np
         if (is_equal_p2d(p(k),p(kc))) then
            cycle
         else
            ka = k
            exit
         endif
      enddo
      !compute the rightmost point from pc
      do k = 1, np
         if (is_equal_p2d(p(k),p(kc)) .or. is_equal_p2d(p(k),p(ka))) cycle
         if (is_on_right_side(p(kc),p(ka),p(k))) ka = k
      enddo
      !print*,'jarvis : ',pa
      if (is_equal_p2d(p(ka),p(lp(1)))) then
         !print*,'retour au point n°1'
         exit
      else
         kc = ka
         nv  = nv + 1
         lp(nv) = ka
      endif
   enddo
end subroutine jarvis

end module mod_ortho
