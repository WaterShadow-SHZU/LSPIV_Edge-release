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

program jarvis_walk

   implicit none
   integer,parameter :: dp = kind(1.0d0)
   !derived types
   type point2D
      real(kind=dp) :: x
      real(kind=dp) :: y
   end type point2D

   ! -- variables --
   integer :: np, nv, k, lu, x, y, io, lp(100)
   type(point2D) :: p(100), q(100)

   p(1)%x = 7  ;  p(1)%y = 4
   p(2)%x = 10 ;  p(2)%y = 0
   p(3)%x = 3  ;  p(3)%y = 7
   p(4)%x = 10 ;  p(4)%y = 10
   p(5)%x = 0  ;  p(5)%y = 10
   p(6)%x = 5  ;  p(6)%y = 5
   p(7)%x = 0  ;  p(7)%y = 0
   p(8)%x = 4  ;  p(8)%y = 6
   np = 8

   call jarvis(p,np,lp,nv)
   print*,'the convex hull would be (0,0), (10,0), (10,10),(0,10)'
   do k = 1, nv
      q(k) = p(lp(k))
      print*,q(k)
   enddo
   print*,'Surface polygone : ',area_poly_convex(q,nv)
   nv  = nv+1
   q(nv) = q(1)
   print*,'Nombre de pixels à l''intérieur : ',number_interior_pixels(q,nv)


   p(1)%x = 5  ;  p(1)%y = 0
   p(2)%x = 10 ;  p(2)%y = 5
   p(3)%x = 5  ;  p(3)%y = 5
   p(4)%x = 0  ;  p(4)%y = 5
   p(5)%x = 5  ;  p(5)%y = 10
   np = 5
   print*,'the convex hull would be (5,0), (10,5), (5,10),(0,5)'
   call jarvis(p,np,lp,nv)
   do k = 1, nv
      q(k) = p(lp(k))
      print*,q(k)
   enddo
   print*,'Surface polygone : ',area_poly_convex(q,nv)
   nv  = nv+1
   q(nv) = q(1)
   print*,'Nombre de pixels à l''intérieur : ',number_interior_pixels(q,nv)

   p(1) = point2D(16,3)
   p(2) = point2D(12,17)
   p(3) = point2D(0,6)
   p(4) = point2D(-4,-6)
   p(5) = point2D(16,6)
   p(6) = point2D(16,-7)
   p(7) = point2D(16,-3)
   p(8) = point2D(17,-4)
   p(9) = point2D(5,19)
   p(10) = point2D(19,-8)
   p(11) = point2D(3,16)
   p(12) = point2D(12,13)
   p(13) = point2D(3,-4)
   p(14) = point2D(17,5)
   p(15) = point2D(-3,15)
   p(16) = point2D(-3,-9)
   p(17) = point2D(0,11)
   p(18) = point2D(-9,-3)
   p(19) = point2D(-4,-2)
   p(20) = point2D(12,10)
   np = 20
   call jarvis(p,np,lp,nv)
   print*,'the convex hull would be (-3,-9), (19,-8), (17,5), (12,17), (5,19), (-3,15) and (-9,-3)'
   do k = 1, nv
      q(k) = p(lp(k))
      print*,q(k)
   enddo
   print*,'Surface polygone : ',area_poly_convex(q,nv)
   nv  = nv+1
   q(nv) = q(1)
   print*,'Nombre de pixels à l''intérieur : ',number_interior_pixels(q,nv)

   print*,'test file test_jarvis.csv'
   open(newunit=lu,file='test_jarvis.csv',form='formatted',status='old')
   np = 0
   do
      read(lu,*,iostat=io) x,y
      if (io /= 0) exit
      np = np+1
      p(np) = point2D(x,y)
   enddo
   close (lu)

   call jarvis(p,np,lp,nv)
   open(newunit=lu,file='test_jarvis_output.csv',form='formatted',status='unknown')
   do k = 1, nv
      write(lu,'(i0,1x,i0)') nint(p(lp(k))%x), nint(p(lp(k))%y)
   enddo
   write(lu,'(i0,1x,i0)') nint(p(lp(1))%x), nint(p(lp(1))%y)
   close(lu)

   do k = 1, nv
      q(k) = p(lp(k))
   enddo
   print*,'Surface polygone : ',area_poly_convex(q,nv)
   nv  = nv+1
   q(nv) = q(1)
   print*,'Nombre de pixels à l''intérieur : ',number_interior_pixels(q,nv)


contains

   logical function is_on_right_side(P0,P1,P)
   !determine if point P is on the right of the segment [P0,P1]
   !is the case if the determinant of vectors P0P1 and P0P is negative
      implicit none
      ! -- prototype --
      type(point2D), intent(in) :: P0, P1, P
      ! -- local variables --
      real(kind=dp) :: v1x, v2x, v1y, v2y
      v1x = p1%x - p0%x  ;  v1y = p1%y - p0%y
      v2x = p%x - p0%x   ;  v2y = p%y - p0%y

      is_on_right_side = ((v1x * v2y - v1y * v2x) <= 0._dp)
      !print*,'is_on_right_side : ', p0%x, p0%y, ' # ',p1%x,p1%y, ' # ',p%x,p%y, ' # ', (v1x * v2y - v1y * v2x)
   end function is_on_right_side


   logical function is_equal_p2d(P,Q)
   !return true if p%x == q%x and p%y == q%y
      implicit none
      ! -- prototype --
      type(point2D), intent(in) :: P, Q
      ! -- local variables --
      real(kind=dp), parameter :: eps = 0.001_dp

      is_equal_p2d = (abs(p%x-q%x) + abs(p%y-q%y)) < eps

   end function is_equal_p2d


   subroutine jarvis(p,np,lp,nv)
   !compute the convex envlop of {P(i), i=1,np}
   !the result is the list of index in p of the vertices {lp(i), i=1,nv}
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
      integer,intent(in) :: np
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


   function number_interior_pixels(p,np)
   !compute the amount of pixels inside the convex polygon p
   !we assume that p is closed : p(1) = p(np)
      implicit none
      !-- prototype --
      integer, intent(in) :: np
      type(point2D), intent(in) :: p(np)
      integer :: number_interior_pixels
      !-- local variables --
      integer :: i, j, num
      real(kind=dp) :: xmin, xmax, ymin, ymax
      type(point2D) :: q

      num = 0
      !search the rectangle that contains the polygon
      xmin = minval(p(1:np)%x)  ;  ymin = minval(p(1:np)%y)
      xmax = maxval(p(1:np)%x)  ;  ymax = maxval(p(1:np)%y)

      do i = int(xmin), int(xmax)
         do j = int(ymin), int(ymax)
            q = point2D(real(i,kind=dp),real(j,kind=dp))
            if (is_inside(q,p,np)) num = num + 1
         enddo
      enddo
      number_interior_pixels = num
   end function number_interior_pixels


   logical function is_inside(xy,p,np)
   ! compute if point2D XY is inside the polygon P given as an array of point2D
   ! we assume the polygon is closed, that is p(np) = p(1)
      implicit none
      ! -- prototype --
      integer, intent(in) :: np
      type(point2D), intent(in) :: xy, p(np)
      ! -- local variables --
      real(kind=dp), parameter :: pi = 2._dp*asin(1._dp) !3.14159265359_dp
      integer :: i, j
      real(kind=dp) :: somme, det, nrm1, nrm2, sin_alpha, pscal, cos_alpha

      somme = 0._dp
      do i = 1, np-1
         j = i+1
         det = (p(i)%x-xy%x)*(p(j)%y-xy%y) - (p(i)%y-xy%y)*(p(j)%x-xy%x)
         pscal = (p(i)%x-xy%x)*(p(j)%x-xy%x) + (p(i)%y-xy%y)*(p(j)%y-xy%y)
         nrm1 = sqrt((p(i)%x-xy%x)**2 + (p(i)%y-xy%y)**2)
         nrm2 = sqrt((p(j)%x-xy%x)**2 + (p(j)%y-xy%y)**2)
         if (abs(nrm1*nrm2) < 1.0e-20_dp) then !xy = p(i) or xy = p(i+1)
            is_inside = .true.
            return
         else
            sin_alpha = det/(nrm1*nrm2)
            cos_alpha = pscal/(nrm1*nrm2)
            if (abs(cos_alpha) <= 1) then
               somme = somme + sign(1._dp,sin_alpha)*acos(cos_alpha)
            endif
         endif
      enddo
      somme = abs(somme) !important car on a pu tourner dans un sens ou l'autre
      is_inside = abs(somme-2._dp*Pi) <= Pi
   end function is_inside

end program jarvis_walk
