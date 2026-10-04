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

module mod_Q_compute

   use iso_fortran_env, only: error_unit
   use lspiv_parameter, only: dp

   contains

subroutine sub_Q_compute(workdir,outdir)

   use iso_fortran_env, only: error_unit
   use lspiv_parameter, only: average_vel, bathy_p, discharge, h_dat, outputs_dir, PIV_param

!     Modifications JLC decembre 2008
!     Moyenne IDW des 3 (au plus) plus proches vitesses
!     JLC, 25 June 2014: add loop for multi-section gauging
!     JLC, 18 October 2016: add measured Q and measured/total Q ratio
!     JLC, 14 December 2016: modified to take new PIV_param.dat format
!     JLC, 2  March 2018: modified for ellipsoid search areas (rx, ry radii)
!     JLC, 2  March 2018: account for surface velocity coefficients at each transect node
!     JLC, 3  December 2019: compute and write mean coefficient, format values in Discharge.dat
!     JLC, 2  May 2020: write all the coefficients in Discharge.dat
!     JLC, 13  May 2020: correction of velocity weighting, and discarding invalid velocity results in neighbour search
!     JLC, 15  May 2020: correction of velocity extrapolation to deal with transect nodes with identical XY
   implicit none
   ! -- prototype --
   character(len=*), intent(in) :: workdir
   character(len=*), intent(inout), optional :: outdir
   ! -- local variables --
   integer :: i, j, compt, k, compt2, jd, jd2, jd3, ios, ii, init, jj
   real(kind=dp) :: Dxp, rx, ry, coeff
   real(kind=dp) :: stage, x, y, z, hh, x0, y0, aa, bb, cc, xpp, pds, fr, fru, frv, a1, a2, d, sum_Q, sum_A
   real(kind=dp) :: sum_Q_measured, sum_Q_coeff_1
   real(kind=dp), allocatable :: xpb(:), xb(:), yb(:), h(:), ub(:), vb(:), ub2(:), vb2(:), vv2(:), ub3(:), vb3(:), vv3(:), &
                                 ubmoy(:), vbmoy(:), dist(:), Q(:), vv(:), vmoy(:), coeffp(:), dmin(:), dmin2(:), dmin3(:)
   real(kind=dp), allocatable :: xp(:), yp(:), u(:), v(:)
   integer, allocatable :: ext(:)
   character(len=80) :: line, line2
   integer :: count1
   integer :: lu14, lu15, lu10
   logical :: ierror


   open(newunit=lu14,file=trim(workdir)//'/'//outputs_dir//'/'//PIV_param,status='old')
   do i = 1, 15
      read(lu14,*)
   enddo
   read(lu14,'(A)') line
   line2 = trim(adjustl(line)) ! get rid of outer spaces
   read(line2,*) rx
   ry = rx ! circular search area by default, then tested for ellipsoid case
   do jj = 1, len_trim(line2)
      if (line2(jj:jj) == ' ') then
         read(line2,*) rx,ry
         exit
      end if
   end do
   read(lu14,*)
   read(lu14,*) Dxp
   close(lu14)

   open(newunit=lu10,file=trim(workdir)//'/'//outputs_dir//'/'//h_dat,status='old')
   read(lu10,*) stage
   close(lu10)


   ! reading average_vel.out file
   if (present(outdir)) then
      open(newunit=lu15,file=trim(outdir)//'/'//outputs_dir//'/'//average_vel,status='old')
   else
      open(newunit=lu15,file=trim(workdir)//'/'//outputs_dir//'/'//average_vel,status='old')
   endif
   !counts the number of records
   count1 = 0
   do
      read(lu15,*,iostat=ios) xpp, x, y, z
      if (ios /= 0) then
         exit
      else
         count1 = count1+1
      endif
   enddo
   allocate (xp(count1),yp(count1),u(count1),v(count1))

   rewind(lu15)
   !i = 0
   do i = 1, count1
      read(lu15,*) xp(i), yp(i), u(i), v(i)
   enddo
   compt2 = count1  !number of velocity points
   close(lu15)


!   Initialize
   sum_Q = 0._dp
   sum_A = 0._dp
   sum_Q_measured = 0._dp
   sum_Q_coeff_1 = 0._dp
   compt = 0 ! total number of wetted bathymetry points
   ierror = .false.


   open(newunit=lu10,file=trim(workdir)//'/'//outputs_dir//'/'//bathy_p,status='old')
   read(lu10,*,end=300)
   read(lu10,*,end=300)
   read(lu10,*,end=300) x0,y0
   read(lu10,*,end=300)
   read(lu10,*,end=300) aa,bb
   read(lu10,*,end=300)

   !counts the number of records
   count1 = 0
   do
      read(lu10,*,iostat=ios) xpp, x, y, z, coeff
      if (ios /= 0) then
         exit
      else
         count1 = count1+1
      endif
   enddo
   ! FIXME: correction à l'aveugle par JLC et JBF pour éviter une erreur de segmentation venant du débordement de tableau ligne 204
   count1 = count1+1

   allocate(xpb(count1),xb(count1),yb(count1),h(count1),ub(count1),vb(count1),&
            ub2(count1),vb2(count1),vv2(count1),ub3(count1),vb3(count1),vv3(count1),&
            ubmoy(count1),vbmoy(count1),dist(count1),Q(count1),vv(count1),vmoy(count1),ext(count1),&
            coeffp(count1),dmin(count1),dmin2(count1),dmin3(count1))
   rewind(lu10)
   read(lu10,*,end=300)
   read(lu10,*,end=300)
   read(lu10,*,end=300) x0, y0
   read(lu10,*,end=300)
   read(lu10,*,end=300) aa, bb
   read(lu10,*,end=300)

   k = 1
   !   First point
   read(lu10,*,end=300) xpp, x, y, z, coeff
   hh = stage-z
   xpb(k) = xpp-0.000001_dp
   xb(k) = x
   yb(k) = y
   h(k) = hh
   coeffp(k) = coeff

   do ii = 1, 100 ! loop on subsections
      do while(hh .le. 0.0001_dp)
         xpb(k) = xpp-0.000001_dp
         xb(k) = x
         yb(k) = y
         h(k) = hh
         coeffp(k) = coeff
         read(lu10,*,end=300) xpp, x, y, z, coeff
         hh = stage-z
      enddo
      !Wetted points
      do while (hh .gt. 0.0001_dp)
         k = k+1
         if (k > count1) then
            write(error_unit,'(a,i0,a,i0)') '>>>> ERROR 1 in Q_compute, index out of bound: ',k,' > ',count1
            return
         endif
         xpb(k) = xpp
         xb(k) = x
         yb(k) = y
         h(k) = hh
         coeffp(k) = coeff
         read(lu10,*,iostat=ios) xpp, x, y, z, coeff
         if (ios /= 0) exit
         hh = stage-z
      enddo
      !Second dry point  (k=compt)
      k = k+1
      if (k > count1) then
         write(error_unit,'(a,i0,a,i0)') '>>>> ERROR 2 in Q_compute, index out of bound: ',k,' > ',count1
         return
      endif
      xpb(k) = xpp+0.000001_dp
      xb(k) = x
      yb(k) = y
      h(k) = hh
      coeffp(k) = coeff

      init = compt+1 ! indice premier point bathy de cette sous-section
      compt = k     !nombre total de points de bathy

      !Computation of edge point coordinates
      if (abs(h(init+1)-h(init)) < 1.0e-20_dp) then
         cc = 0._dp
      else
         cc = -h(init)/(h(init+1)-h(init))
      endif
      xpb(init) =  xpb(init)+cc*(xpb(init+1)-xpb(init))
      xb(init)  =  xb(init)+cc*(xb(init+1)-xb(init))
      yb(init)  =  yb(init)+cc*(yb(init+1)-yb(init))
      h(init)   =  0._dp
      coeffp(init) =  coeffp(init)+cc*(coeffp(init+1)-coeffp(init))

      if (abs(h(compt)-h(compt-1)) > 1.0e-20_dp) then
         cc = 0._dp
      else
         cc = -h(compt)/(h(compt-1)-h(compt))
      endif

      k = k+1 ! stockage du point suivant pour sous-section suivante
      xpb(k) = xpb(compt)-0.000001_dp
      xb(k)  = xb(compt)
      yb(k)  = yb(compt)
      h(k)   = h(compt)
      coeffp(k) = coeffp(compt)

      xpb(compt) =  xpb(compt)+cc*(xpb(compt-1)-xpb(compt))
      xb(compt)  =  xb(compt)+cc*(xb(compt-1)-xb(compt))
      yb(compt)  =  yb(compt)+cc*(yb(compt-1)-yb(compt))
      h(compt)   =  0._dp
      coeffp(compt) =  coeffp(compt)+cc*(coeffp(compt-1)-coeffp(compt))

      do i = init+1, compt-1
         dmin(i)  = 1._dp
         dmin2(i) = 1._dp
         dmin3(i) = 1._dp
         jd  = 0
         jd2 = 0
         jd3 = 0
         do j = 1, compt2
            if ((abs(u(j)) > 1.0e-20_dp) .or. (abs(v(j)) > 1.0e-20_dp)) then ! excluding invalid velocity results
               d = sqrt(((xp(j)-xb(i))/rx)**2 +((yp(j)-yb(i))/ry)**2)
              if (d < dmin3(i)) then
                if (d < dmin2(i)) then
                     if (d < dmin(i)) then
                       dmin3(i) = dmin2(i)
                      jd3 = jd2
                          dmin2(i) = dmin(i)
                      jd2 = jd
                          dmin(i) = d
                          jd = j
                   else
                        dmin3(i) = dmin2(i)
                        jd3 = jd2
                        dmin2(i) = d
                        jd2 = j
                     endif
                  else
                     dmin3(i) = d
                     jd3 = j
                  endif
               endif
            endif
         enddo
         if (jd .ne. 0) then
            ub(i) = u(jd)
            vb(i) = v(jd)
            vv(i) = -bb*ub(i)+aa*vb(i) ! normal velocity
         else
            vv(i) = 0._dp
         endif
         if (jd2.ne.0) then
            ub2(i) = u(jd2)
            vb2(i) = v(jd2)
            vv2(i) = -bb*ub2(i)+aa*vb2(i) ! normal velocity
            !vv2(i)=coeff_surface*sqrt(ub2(i)**2+vb2(i)**2)
         else
            vv2(i) = 0._dp
         endif
         if (jd3.ne.0) then
            ub3(i) = u(jd3)
            vb3(i) = v(jd3)
            vv3(i) = -bb*ub3(i)+aa*vb3(i) ! normal velocity
            !vv3(i)=coeff_surface*sqrt(ub3(i)**2+vb3(i)**2)
         else
            vv3(i) = 0._dp
         endif
      enddo

      do i = init+1,compt-1
         pds = 0._dp
         ! mid-section integration method
         dist(i) = abs(xpb(i+1)-xpb(i-1))/2._dp
         ! mean-section integration method
         if (dmin(i) < 0.001_dp) dmin(i) = 0.001_dp
         if (dmin2(i) < 0.001_dp) dmin2(i) = 0.001_dp
         if (dmin3(i) < 0.001_dp) dmin3(i) = 0.001_dp
         if (abs(vv(i)) > 1.0e-20_dp) pds = pds+1._dp/dmin(i)
         if (abs(vv2(i)) > 1.0e-20_dp) pds = pds+1._dp/dmin2(i)
         if (abs(vv3(i)) > 1.0e-20_dp) pds = pds+1._dp/dmin3(i)
         if (abs(pds) > 1.0e-20_dp) then
            vmoy(i)  = coeffp(i)*(vv(i)/dmin(i)+vv2(i)/dmin2(i)+vv3(i)/dmin3(i))/pds
            ubmoy(i) = coeffp(i)*(ub(i)/dmin(i)+ub2(i)/dmin2(i)+ub3(i)/dmin3(i))/pds
            vbmoy(i) = coeffp(i)*(vb(i)/dmin(i)+vb2(i)/dmin2(i)+vb3(i)/dmin3(i))/pds
         else
            vmoy(i)  = 0._dp  ;  ubmoy(i) = 0._dp  ;  vbmoy(i) = 0._dp
         endif
      enddo
      vmoy(init)  = 0._dp  ;  ubmoy(init) = 0._dp  ;  vbmoy(init) = 0._dp
      vmoy(compt)  = 0._dp  ;  ubmoy(compt) = 0._dp  ;  vbmoy(compt) = 0._dp
!       h(init)  = h(init+1)/2._dp
!       h(compt) = h(compt-1)/2._dp
      dist(init)  = abs(xpb(init)-xpb(init+1))/2._dp
      dist(compt) = abs(xpb(compt-1)-xpb(compt))/2._dp

      !interpolation and extrapolation (constant Froude assumption)
      do i = init,compt
         ext(i) = 0
         if (abs(vmoy(i)) < 1.0e-20_dp) then ! pas de vitesse, on interpole ou extrapole
            k = i+1
            !do while((k .le. compt) .and. (vmoy(k) .eq. 0._dp)) !! débordement de tableau pour k=compt+1
            do while (k .le. compt) ! on cherche le premier point suivant qui a une vitesse
               if (abs(vmoy(k)) < 1.0e-20_dp) then
                  k = k+1
               else
                  exit
               endif
            enddo
            j = i-1
            !do while( (j.ge.1) ).and. (vmoy(j).eq.0._dp) ) !! débordement de tableau pour j=0
            do while (j.ge.1) ! on cherche le premier point précédent qui a une vitesse
               if (abs(vmoy(j)) < 1.0e-20_dp) then
                  j = j-1
               else
                  exit
               endif
            enddo
            if (k.le.compt) then ! on a trouve un point a droite en k
               if (j .ge. 1) then ! on a trouve deux vitesses, on est en interpolation

                 ! DEBUT definition des coefficients de ponderation a1 et a2 pour interpolation du Froude (gestion des distances nulles)
                  if (abs(xpb(k)-xpb(i)) < 0.0001_dp) then
                     if (abs(xpb(j)-xpb(i)) < 0.0001_dp) then
                        a1 = 1._dp
                        a2 = 1._dp
                     else
                        a1 = 1._dp
                        a2 = 0._dp
                     endif
                  elseif (abs(xpb(j)-xpb(i)) < 0.0001) then
                     a1 = 0._dp
                     a2 = 1._dp
                  else
                     a1 = 1._dp/abs(xpb(k)-xpb(i))
                     a2 = 1._dp/abs(xpb(j)-xpb(i))
                  endif
                  fru = (a1*ubmoy(k)/sqrt(h(k))+a2*ubmoy(j)/sqrt(h(j)))/(a1+a2)
                  frv = (a1*vbmoy(k)/sqrt(h(k))+a2*vbmoy(j)/sqrt(h(j)))/(a1+a2)
                  fr = -bb*fru + aa*frv
               else ! on a pas de vitesse en j, on est en extrapolation
                  fru = ubmoy(k)/sqrt(h(k))
                  frv = vbmoy(k)/sqrt(h(k))
               endif
            else
               if (j .ge. 1) then ! on a pas de vitesse en k, on est en extrapolation
                  fru = ubmoy(j)/sqrt(h(j))
                  frv = vbmoy(j)/sqrt(h(j))
               else ! on a pas de vitesse
                  fru = 0._dp
                  frv = 0._dp
                  fr = 0._dp
               endif
            endif

            fr = -bb*fru + aa*frv

            ubmoy(i)  = sqrt(h(i))*fru
            vbmoy(i)  = sqrt(h(i))*frv
            vmoy(i)  = sqrt(h(i))*fr

            ext(i) = 1
         endif
         Q(i) = dist(i)*h(i)*vmoy(i)
      enddo
         !aux bords: moyenne entre vitesse a mi-chemin et vitesse nulle au bord
!       vmoy(init) = vmoy(init+1)*0.5_dp
!       vbmoy(init) = vbmoy(init+1)*0.5_dp
!       ubmoy(init) = ubmoy(init+1)*0.5_dp
!       vmoy(compt) = vmoy(compt-1)*0.5_dp
!       vbmoy(compt) = vbmoy(compt-1)*0.5_dp
!       ubmoy(compt) = ubmoy(compt-1)*0.5_dp

      Q(init:compt) = dist(init:compt)*h(init:compt)*vmoy(init:compt)

      !Discharge sum
      coeffp(init) = coeffp(init+1)
      coeffp(compt) = coeffp(compt-1)
      do i = init, compt
         sum_Q = sum_Q+Q(i)
         sum_A = sum_A+h(i)*dist(i)
         sum_Q_coeff_1 = sum_Q_coeff_1+Q(i)/coeffp(i)
         if (ext(i) .eq. 0) sum_Q_measured=sum_Q_measured+Q(i)
      enddo

   enddo ! End of loop on subsections

   300  continue

   close(lu10)
   write(*,*)'#######################################'
   write(*,'(a,f10.3,a)') ' ### Total Discharge:',sum_Q,' m3/s ###'
   write(*,'(a,f10.3,a)') ' ### Wetted Area:      ',sum_A,' m2 ###'
   write(*,'(a,f10.3,a)') ' ### Mean Velocity:   ',sum_Q/sum_A,' m/s ###'
   write(*,'(a,f10.3,a)') ' ### Water stage:       ',stage,' m ###'
   if (abs(sum_Q) > 1.0e-20) then
      write(*,'(a,f10.3,a)') ' ### Mean Coefficient:    ',sum_Q/sum_Q_coeff_1,' ###'
   else
      write(*,'(a)') ' ### Mean Coefficient:           N/A ###'
   endif
   write(*,*) '#######################################'


!sauvegarde des vitesses interpolees pour le calcul du debit
   if (present(outdir)) then
      open(newunit=lu10,file=trim(outdir)//'/'//outputs_dir//'/'//discharge,status='unknown')
   else
      open(newunit=lu10,file=trim(workdir)//'/'//outputs_dir//'/'//discharge,status='unknown')
   endif

   if (abs(sum_Q) > 1.0e-20) then
      write(lu10,'(6f10.3)') stage,sum_Q,sum_A,sum_Q/sum_A,sum_Q_measured,sum_Q/sum_Q_coeff_1
   else
      write(lu10,'(5f10.3)') stage,sum_Q,sum_A,sum_Q/sum_A,sum_Q_measured
   endif

   do i = 1, compt
      write(lu10,'(I4,7f10.3,I2,f10.3)') i,xpb(i),xb(i),yb(i),h(i),ubmoy(i),vbmoy(i),vmoy(i),ext(i),coeffp(i)
   enddo

   close(lu10)

   deallocate(xpb,xb,yb,h,ub,vb,ub2,vb2,vv2,ub3,vb3,vv3,ubmoy,vbmoy,dist,Q,vv,vmoy,ext,coeffp)

end subroutine sub_Q_compute

end module mod_Q_compute
