!=======================================================================
!=======================================================================
!=======================================================================
!=======================================================================
subroutine output_frame()
  use amr_commons
  use pm_commons
  use hydro_commons
#ifdef RT
  use rt_parameters
  use rt_hydro_commons
#endif
  implicit none
#ifndef WITHOUTMPI
  include "mpif.h"
#endif
  
!   integer::dummy_io,info
!   integer,parameter::tag=100

!   character(len=5) :: istep_str
!   character(len=100) :: moviedir, moviecmd, infofile, sinkfile
! #ifdef SOLVERmhd
!   character(len=100),dimension(0:NVAR+6) :: moviefiles
! #else
!   character(len=100),dimension(0:NVAR+2) :: moviefiles
! #endif
!   integer::icell,ncache,iskip,irad,ngrid,nlevelmax_frame
!   integer::ilun,nx_loc,ipout,npout,npart_out,ind,ix,iy,iz
!   integer::imin,imax,jmin,jmax,ii,jj,kk,ll
!   character(LEN=80)::fileloc
!   character(LEN=5)::nchar,dummy
!   real(dp)::scale,scale_nH,scale_T2,scale_l,scale_d,scale_t,scale_v
!   real(dp)::xcen,ycen,zcen,delx,dely,delz
!   real(dp)::xtmp,ytmp,ztmp,smooth,dist_camera,theta_cam,phi_cam
!   real(dp)::xleft_frame,xright_frame,yleft_frame,yright_frame,zleft_frame,zright_frame,rr
!   real(dp)::xleft,xright,yleft,yright,zleft,zright,xcentre,ycentre,zcentre
!   real(dp)::xxleft,xxright,yyleft,yyright,zzleft,zzright,xxcentre,yycentre,zzcentre
!   real(dp)::xpf,ypf,zpf
!   real(dp)::dx_frame,dy_frame,dx,dx_loc,dx_min,pers_corr
!   real(dp)::dx_cell,dy_cell,dz_cell,dvol
!   real(kind=8)::cell_value
!   integer ,dimension(1:nvector)::ind_grid,ind_cell
!   logical,dimension(1:nvector)::ok
!   real(dp),dimension(1:3)::skip_loc
!   real(dp),dimension(1:twotondim,1:3)::xc
!   real(dp),dimension(1:nvector,1:ndim)::xx
!   real(kind=8),dimension(:,:,:),allocatable::data_frame,data_frame_all
!   real(kind=8),dimension(:,:),allocatable::dens,dens_all,vol,vol_all
!   real(kind=4),dimension(:,:),allocatable::data_single
!   real(kind=8) :: z1,z2,om0in,omLin,hubin,Lbox
!   real(kind=8) :: observer(3),thetay,thetaz,theta,phi,temp,e
!   real(kind=8) :: pi=3.14159265359
!   integer::igrid,jgrid,ipart,jpart,idim,icpu,ilevel,next_part
!   integer::i,j,ig,ip,npart1
!   integer::nalloc1,nalloc2
!   integer::proj_ind,l,nh_temp,nw_temp
!   real(dp),dimension(8)::xcube = (/-1.0,-1.0,-1.0,-1.0, 1.0, 1.0, 1.0, 1.0/)
!   real(dp),dimension(8)::ycube = (/-1.0,-1.0, 1.0, 1.0,-1.0,-1.0, 1.0, 1.0/)
!   real(dp),dimension(8)::zcube = (/-1.0, 1.0,-1.0, 1.0,-1.0, 1.0,-1.0, 1.0/)
!   real(dp)::minxcube,maxxcube,minycube,maxycube,minzcube,maxzcube,xpc,ypc,zpc
!   integer,dimension(1:nvector),save::ind_part,ind_grid_part
!   logical::opened
!   character(len=1)::temp_string

! #ifdef RT
!   character(len=100),dimension(1:NGROUPS) :: rt_moviefiles
!   real(kind=8),dimension(:,:,:),allocatable::rt_data_frame,rt_data_frame_all
! #endif  

!   nh_temp    = nh_frame
!   nw_temp    = nw_frame
  
!  do proj_ind=1,LEN(trim(proj_axis)) 
!   opened=.false.

! #if NDIM > 1
!   if(imov<1)imov=1
!   if(imov>imovout)return

!   ! Determine the filename, dir, etc
!   if(myid==1)write(*,*)'Computing and dumping movie frame'

!   call title(imov, istep_str)
!   write(temp_string,'(I1)') proj_ind
!   moviedir = 'movie'//trim(temp_string)//'/'
!   moviecmd = 'mkdir -p '//trim(moviedir)
!   if(myid==1) write(*,*) "Writing frame ", istep_str
!   if(.not.withoutmkdir) then 
! #ifdef NOSYSTEM
!      if(myid==1)call PXFMKDIR(TRIM(moviedir),LEN(TRIM(moviedir)),O'755',info)  
! #else
!      if(myid==1)call system(moviecmd)
! #endif
!   endif
  
!   infofile = trim(moviedir)//'info_'//trim(istep_str)//'.txt'
!   if(myid==1)call output_info(infofile)
  
!   moviefiles(0) = trim(moviedir)//'temp_'//trim(istep_str)//'.map'
!   moviefiles(1) = trim(moviedir)//'dens_'//trim(istep_str)//'.map'
!   moviefiles(2) = trim(moviedir)//'vx_'//trim(istep_str)//'.map'
!   moviefiles(3) = trim(moviedir)//'vy_'//trim(istep_str)//'.map'
! #if NDIM>2
!   moviefiles(4) = trim(moviedir)//'vz_'//trim(istep_str)//'.map'
! #endif
! #if NDIM==2
!   moviefiles(4) = trim(moviedir)//'pres_'//trim(istep_str)//'.map'
! #endif
! #if NDIM>2
!   moviefiles(5) = trim(moviedir)//'pres_'//trim(istep_str)//'.map'
! #endif
! #if NVAR>5
!   do ll=6,NVAR
!     write(dummy,'(I3.1)') ll
!     moviefiles(ll) = trim(moviedir)//'var'//trim(adjustl(dummy))//'_'//trim(istep_str)//'.map'
!  end do
! #endif
! #ifdef SOLVERmhd
!   moviefiles(6) = trim(moviedir)//'bxl_'//trim(istep_str)//'.map'
!   moviefiles(7) = trim(moviedir)//'byl_'//trim(istep_str)//'.map'
!   moviefiles(8) = trim(moviedir)//'bzl_'//trim(istep_str)//'.map'
!   moviefiles(NVAR+1) = trim(moviedir)//'bxr_'//trim(istep_str)//'.map'
!   moviefiles(NVAR+2) = trim(moviedir)//'byr_'//trim(istep_str)//'.map'
!   moviefiles(NVAR+3) = trim(moviedir)//'bzr_'//trim(istep_str)//'.map'
!   moviefiles(NVAR+4) = trim(moviedir)//'pmag_'//trim(istep_str)//'.map'
!   moviefiles(NVAR+5) = trim(moviedir)//'dm_'//trim(istep_str)//'.map'
!   moviefiles(NVAR+6) = trim(moviedir)//'stars_'//trim(istep_str)//'.map'
! #else
!   moviefiles(NVAR+1) = trim(moviedir)//'dm_'//trim(istep_str)//'.map'
!   moviefiles(NVAR+2) = trim(moviedir)//'stars_'//trim(istep_str)//'.map'
! #endif

! #ifdef RT
!   ! Can generate mass weighted averages of cN_i for each group i
!   if(rt) then
!      do ll=1,NGROUPS
!         write(dummy,'(I3.1)') ll
!         rt_moviefiles(ll) = trim(moviedir)//'Fp'//trim(adjustl(dummy))//'_'//trim(istep_str)//'.map'
!      end do
!   endif
! #endif

!   ! sink filename
!   if(sink)then
!     sinkfile = trim(moviedir)//'sink_'//trim(istep_str)//'.txt'
!     if(myid==1.and.proj_ind==1) call output_sink_csv(sinkfile)
!   endif
  
!   if(levelmax_frame==0)then
!      nlevelmax_frame=nlevelmax
!   else if (levelmax_frame.gt.nlevelmax)then
!      nlevelmax_frame=nlevelmax
!   else
!      nlevelmax_frame=levelmax_frame
!   endif

!   ! Conversion factor from user units to cgs units
!   call units(scale_l,scale_t,scale_d,scale_v,scale_nH,scale_T2)

!   ! Local constants
!   nx_loc=(icoarse_max-icoarse_min+1)
!   skip_loc=(/0.0d0,0.0d0,0.0d0/)
!   if(ndim>0)skip_loc(1)=dble(icoarse_min)
!   if(ndim>1)skip_loc(2)=dble(jcoarse_min)
!   if(ndim>2)skip_loc(3)=dble(kcoarse_min)
!   scale=boxlen/dble(nx_loc)

!   ! Compute frame boundaries
!   if(proj_axis(proj_ind:proj_ind).eq.'x')then
!     xcen=ycentre_frame(proj_ind*4-3)+ycentre_frame(proj_ind*4-2)*aexp+ycentre_frame(proj_ind*4-1)*aexp**2+ycentre_frame(proj_ind*4)*aexp**3
!     ycen=zcentre_frame(proj_ind*4-3)+zcentre_frame(proj_ind*4-2)*aexp+zcentre_frame(proj_ind*4-1)*aexp**2+zcentre_frame(proj_ind*4)*aexp**3
!     zcen=xcentre_frame(proj_ind*4-3)+xcentre_frame(proj_ind*4-2)*aexp+xcentre_frame(proj_ind*4-1)*aexp**2+xcentre_frame(proj_ind*4)*aexp**3
!   elseif(proj_axis(proj_ind:proj_ind).eq.'y')then
!     xcen=xcentre_frame(proj_ind*4-3)+xcentre_frame(proj_ind*4-2)*aexp+xcentre_frame(proj_ind*4-1)*aexp**2+xcentre_frame(proj_ind*4)*aexp**3
!     ycen=zcentre_frame(proj_ind*4-3)+zcentre_frame(proj_ind*4-2)*aexp+zcentre_frame(proj_ind*4-1)*aexp**2+zcentre_frame(proj_ind*4)*aexp**3
!     zcen=ycentre_frame(proj_ind*4-3)+ycentre_frame(proj_ind*4-2)*aexp+ycentre_frame(proj_ind*4-1)*aexp**2+ycentre_frame(proj_ind*4)*aexp**3
!   else
!     xcen=xcentre_frame(proj_ind*4-3)+xcentre_frame(proj_ind*4-2)*aexp+xcentre_frame(proj_ind*4-1)*aexp**2+xcentre_frame(proj_ind*4)*aexp**3
!     ycen=ycentre_frame(proj_ind*4-3)+ycentre_frame(proj_ind*4-2)*aexp+ycentre_frame(proj_ind*4-1)*aexp**2+ycentre_frame(proj_ind*4)*aexp**3
!     zcen=zcentre_frame(proj_ind*4-3)+zcentre_frame(proj_ind*4-2)*aexp+zcentre_frame(proj_ind*4-1)*aexp**2+zcentre_frame(proj_ind*4)*aexp**3
!   endif
!   delx=deltax_frame(proj_ind*2-1)+deltax_frame(proj_ind*2)/aexp
!   dely=deltay_frame(proj_ind*2-1)+deltay_frame(proj_ind*2)/aexp
!   delz=deltaz_frame(proj_ind*2-1)+deltaz_frame(proj_ind*2)/aexp

!   xleft_frame=xcen-delx/2.
!   xright_frame=xcen+delx/2.
!   yleft_frame=ycen-dely/2.
!   yright_frame=ycen+dely/2.
!   zleft_frame=zcen-delz/2.
!   zright_frame=zcen+delz/2.

!   ! Camera properties
!   if(cosmo) then
!      theta_cam  = theta_camera(proj_ind)*pi/180.+aexp*dtheta_camera(proj_ind)*pi/180.
!      phi_cam    = phi_camera(proj_ind)*pi/180.+aexp*dphi_camera(proj_ind)*pi/180.
!   else
!      theta_cam  = theta_camera(proj_ind)*pi/180.+t*dtheta_camera(proj_ind)*pi/180.
!      phi_cam    = phi_camera(proj_ind)*pi/180.+t*dphi_camera(proj_ind)*pi/180.
!   endif
!   dist_camera   = boxlen
!   if((focal_camera(proj_ind).le.0D0).or.(focal_camera(proj_ind).gt.dist_camera)) focal_camera(proj_ind)=dist_camera

!   do i=1,8
!      xtmp     = cos(theta_cam)*xcube(i)+sin(theta_cam)*ycube(i)
!      ytmp     = cos(theta_cam)*ycube(i)-sin(theta_cam)*xcube(i)
!      xcube(i) = xtmp
!      ycube(i) = ytmp
!      ytmp     = cos(phi_cam)*ycube(i)+sin(phi_cam)*zcube(i)
!      ztmp     = cos(phi_cam)*zcube(i)-sin(phi_cam)*ycube(i)
!      ycube(i) = ytmp
!      zcube(i) = ztmp
!   enddo
!   minxcube = minval(xcube)
!   maxxcube = maxval(xcube)
!   minycube = minval(ycube)
!   maxycube = maxval(ycube)
!   minzcube = minval(zcube)
!   maxzcube = maxval(zcube)
  
!   ! Allocate image
! #ifdef SOLVERmhd
!   allocate(data_frame(1:nw_frame,1:nh_frame,0:NVAR+6))
! #else
!   allocate(data_frame(1:nw_frame,1:nh_frame,0:NVAR+2))
! #endif
! #ifdef RT
!   if(rt) then
!      allocate(rt_data_frame(1:nw_frame,1:nh_frame,1:NGROUPS))
!      rt_data_frame(:,:,:) = 0d0
!   endif
! #endif
!   allocate(dens(1:nw_frame,1:nh_frame))
!   allocate(vol(1:nw_frame,1:nh_frame))
!   data_frame=0d0
!   dens=0d0
!   vol=0d0
!   dx_frame=delx/dble(nw_frame)
!   dy_frame=dely/dble(nh_frame)

!   if(hydro) then
!      ! Loop over levels
!      do ilevel=levelmin,nlevelmax_frame
   
!         ! Mesh size at level ilevel in coarse cell units
!         dx=0.5D0**ilevel
        
!         ! Set position of cell centres relative to grid centre
!         do ind=1,twotondim
!            iz=(ind-1)/4
!            iy=(ind-1-4*iz)/2
!            ix=(ind-1-2*iy-4*iz)
!            if(ndim>0)xc(ind,1)=(dble(ix)-0.5D0)*dx
!            if(ndim>1)xc(ind,2)=(dble(iy)-0.5D0)*dx
!            if(ndim>2)xc(ind,3)=(dble(iz)-0.5D0)*dx
!         end do
     
!         dx_loc=dx*scale
!         dx_min=0.5D0**nlevelmax*scale
!         ncache=active(ilevel)%ngrid
   
!         ! Loop over grids by vector sweeps
!         do igrid=1,ncache,nvector
!            ngrid=MIN(nvector,ncache-igrid+1)
!            do i=1,ngrid
!               ind_grid(i)=active(ilevel)%igrid(igrid+i-1)
!            end do
!            ! Loop over cells
!            do ind=1,twotondim
!               ! Gather cell indices
!               iskip=ncoarse+(ind-1)*ngridmax
!               do i=1,ngrid
!                  ind_cell(i)=iskip+ind_grid(i)
!               end do
!               ! Gather cell centre positions
!               do idim=1,ndim
!                  do i=1,ngrid
!                     xx(i,idim)=xg(ind_grid(i),idim)+xc(ind,idim)
!                  end do
!               end do
!               ! Rescale position from code units to user units
!               do idim=1,ndim
!                  do i=1,ngrid
!                     xx(i,idim)=(xx(i,idim)-skip_loc(idim))*scale
!                  end do
!               end do

!               ! Projection
!               do i=1,ngrid
!                     xx(i,1)=xx(i,1)-boxlen/2.0
!                     xx(i,2)=xx(i,2)-boxlen/2.0
!                     xx(i,3)=xx(i,3)-boxlen/2.0
!                     xtmp=cos(theta_cam)*xx(i,1)+sin(theta_cam)*xx(i,2)
!                     ytmp=cos(theta_cam)*xx(i,2)-sin(theta_cam)*xx(i,1)
!                     xx(i,1)=xtmp
!                     xx(i,2)=ytmp
!                     ytmp=cos(phi_cam)*xx(i,2)+sin(phi_cam)*xx(i,3)
!                     ztmp=cos(phi_cam)*xx(i,3)-sin(phi_cam)*xx(i,2)
!                     xx(i,2)=ytmp
!                     xx(i,3)=ztmp
                    
!                     if(proj_axis(proj_ind:proj_ind).eq.'x')then
!                       if(perspective_camera(proj_ind))then
!                          xx(i,2)=xx(i,2)*focal_camera(proj_ind)/(dist_camera-xx(i,1))
!                          xx(i,3)=xx(i,3)*focal_camera(proj_ind)/(dist_camera-xx(i,1))
!                       endif
!                       xx(i,2)=xx(i,2)+boxlen/2.0
!                       xx(i,3)=xx(i,3)+boxlen/2.0
!                     elseif(proj_axis(proj_ind:proj_ind).eq.'y')then
!                       if(perspective_camera(proj_ind))then
!                          xx(i,1)=xx(i,1)*focal_camera(proj_ind)/(dist_camera-xx(i,2))
!                          xx(i,3)=xx(i,3)*focal_camera(proj_ind)/(dist_camera-xx(i,2))
!                       endif
!                       xx(i,1)=xx(i,1)+boxlen/2.0
!                       xx(i,3)=xx(i,3)+boxlen/2.0
!                     else
!                       if(perspective_camera(proj_ind))then
!                          xx(i,1)=xx(i,1)*focal_camera(proj_ind)/(dist_camera-xx(i,3))
!                          xx(i,2)=xx(i,2)*focal_camera(proj_ind)/(dist_camera-xx(i,3))
!                       endif
!                       xx(i,1)=xx(i,1)+boxlen/2.0
!                       xx(i,2)=xx(i,2)+boxlen/2.0
!                     endif
!               end do
              
!               ! Check if cell is to be considered
!               do i=1,ngrid
!                  ok(i)=son(ind_cell(i))==0.or.ilevel==nlevelmax_frame
!                  if(ivar_refine>0.and.zoom_only) then
!                    ok(i)=ok(i).and. &
!                       & (uold(ind_cell(i),ivar_refine)/uold(ind_cell(i),1) &
!                       & > var_cut_refine)
!                  endif
!               end do
   
!               do i=1,ngrid
!                  if(ok(i))then
!                     ! Check if the cell intersect the domain
!                     if(proj_axis(proj_ind:proj_ind).eq.'x')then
!                       if(perspective_camera(proj_ind))then
!                          pers_corr= focal_camera(proj_ind)/(dist_camera-xx(i,1))
!                       else
!                          pers_corr= 1.0        
!                       endif
!                       xcentre     = xx(i,2)
!                       ycentre     = xx(i,3)
!                       zcentre     = xx(i,1)+boxlen/2.
!                       xleft       = xcentre-abs(minycube)*dx_loc/2.*pers_corr 
!                       xright      = xcentre+abs(maxycube)*dx_loc/2.*pers_corr 
!                       yleft       = ycentre-abs(minzcube)*dx_loc/2.*pers_corr 
!                       yright      = ycentre+abs(maxzcube)*dx_loc/2.*pers_corr 
!                       zleft       = zcentre-dx_loc/2.
!                       zright      = zcentre+dx_loc/2.
!                     elseif(proj_axis(proj_ind:proj_ind).eq.'y')then
!                       if(perspective_camera(proj_ind))then
!                          pers_corr= focal_camera(proj_ind)/(dist_camera-xx(i,2))
!                       else
!                          pers_corr= 1.0
!                       endif
!                       xcentre     = xx(i,1)
!                       ycentre     = xx(i,3)
!                       zcentre     = xx(i,2)+boxlen/2.
!                       xleft       = xcentre-abs(minxcube)*dx_loc/2.*pers_corr
!                       xright      = xcentre+abs(maxxcube)*dx_loc/2.*pers_corr
!                       yleft       = ycentre-abs(minzcube)*dx_loc/2.*pers_corr
!                       yright      = ycentre+abs(maxzcube)*dx_loc/2.*pers_corr
!                       zleft       = zcentre-dx_loc/2.
!                       zright      = zcentre+dx_loc/2.
!                     else
!                       if(perspective_camera(proj_ind))then
!                          pers_corr= focal_camera(proj_ind)/(dist_camera-xx(i,3))
!                       else
!                          pers_corr= 1.0
!                       endif
!                       xcentre     = xx(i,1)
!                       ycentre     = xx(i,2)
!                       zcentre     = xx(i,3)+boxlen/2.
!                       xleft       = xcentre-abs(minxcube)*dx_loc/2.*pers_corr
!                       xright      = xcentre+abs(maxxcube)*dx_loc/2.*pers_corr
!                       yleft       = ycentre-abs(minycube)*dx_loc/2.*pers_corr
!                       yright      = ycentre+abs(maxycube)*dx_loc/2.*pers_corr
!                       zleft       = zcentre-dx_loc/2.
!                       zright      = zcentre+dx_loc/2.
!                     endif
! #if NDIM>2                 
!                     if(    xright.lt.xleft_frame.or.xleft.ge.xright_frame.or.&
!                          & yright.lt.yleft_frame.or.yleft.ge.yright_frame.or.&
!                          & zright.lt.zleft_frame.or.zleft.ge.zright_frame)cycle
! #else
!                     if(    xright.lt.xleft_frame.or.xleft.ge.xright_frame.or.&
!                          & yright.lt.yleft_frame.or.yleft.ge.yright_frame)cycle
! #endif
!                     ! Compute map indices for the cell
!                     if(xleft>xleft_frame)then
!                        imin=min(int((xleft-xleft_frame)/dx_frame)+1,nw_frame)
!                     else
!                        imin=1
!                     endif
!                     imax=min(int((xright-xleft_frame)/dx_frame)+1,nw_frame)
!                     if(yleft>yleft_frame)then
!                        jmin=min(int((yleft-yleft_frame)/dy_frame)+1,nh_frame) ! change
!                     else
!                        jmin=1
!                     endif
!                     jmax=min(int((yright-yleft_frame)/dy_frame)+1,nh_frame) ! change
                    
!                     ! Fill up map with projected mass
!                     do ii=imin,imax
!                        ! Pixel x-axis position
!                        xxleft      = xleft_frame+dble(ii-1)*dx_frame
!                        xxright     = xxleft+dx_frame
!                        xxcentre    = xxleft+0.5*dx_frame
!                        dx_cell     = min(xxright,xright)-max(xxleft,xleft)
!                        do jj=jmin,jmax
!                           ! Pixel y-axis position
!                           yyleft   = yleft_frame+dble(jj-1)*dy_frame
!                           yyright  = yyleft+dy_frame
!                           yycentre = yyleft+0.5*dy_frame
!                           dy_cell  = min(yyright,yright)-max(yyleft,yleft)
!                           ! Reproject in AMR coordinates
!                           ! Pixel position in cell reference frame
!                           xpc      = xxcentre-xcentre
!                           ypc      = yycentre-ycentre
!                           ypc      = cos(-phi_cam)*ypc
!                           xtmp     = cos(-theta_cam)*xpc+sin(-theta_cam)*ypc
!                           ytmp     = cos(-theta_cam)*ypc-sin(-theta_cam)*xpc
!                           xpc      = xtmp
!                           ypc      = ytmp
!                           if((abs(xpc).le.dx_loc/2.*pers_corr).and.(abs(ypc).le.dx_loc/2.*pers_corr))then
!                              ! Intersection volume
!                              dvol        = dx_cell*dy_cell
!                              dens(ii,jj) = dens(ii,jj)+dvol*uold(ind_cell(i),1)
!                              vol(ii,jj)  = vol(ii,jj)+dvol
                             
!                              data_frame(ii,jj,1)=data_frame(ii,jj,1)+dvol*uold(ind_cell(i),1)**2
! #ifdef SOLVERmhd
!                              do kk=2,NVAR+3
! #else                       
!                              do kk=2,NVAR
! #endif
!                                 if(movie_vars(kk).eq.1) data_frame(ii,jj,kk)=data_frame(ii,jj,kk)+dvol*uold(ind_cell(i),kk)
!                              end do
      
! #ifdef RT
!                              if(rt) then
!                                 do kk=1,NGROUPS
!                                    if(rt_movie_vars(kk).eq.1) then
!                                       rt_data_frame(ii,jj,kk) = rt_data_frame(ii,jj,kk) &
!                                            + dvol * rtuold(ind_cell(i), 1+(kk-1)*(ndim+1)) * rt_c_cgs &
!                                                   * max(uold(ind_cell(i),1),smallr) ! mass-weighted
!                                    endif
!                                 end do
!                              endif
! #endif
      
                             
!                              if (movie_vars(0).eq.1)then
!                                !Get temperature
!                                e=0.0d0
!                                do idim=1,ndim
!                                   e=e+0.5*uold(ind_cell(i),idim+1)**2/max(uold(ind_cell(i),1),smallr)
!                                enddo
! #if NENER>0
!                                do irad=0,nener-1
!                                   e=e+uold(ind_cell(i),inener+irad)
!                                enddo
! #endif
! #ifdef SOLVERmhd
!                                do idim=1,ndim 
!                                   e=e+0.125d0*(uold(ind_cell(i),idim+ndim+2)+uold(ind_cell(i),idim+nvar))**2
!                                enddo
! #endif
!                                temp=(gamma-1.0)*(uold(ind_cell(i),ndim+2)-e) !pressure
!                                temp=max(temp/max(uold(ind_cell(i),1),smallr),smallc**2)*scale_T2 !temperature in K
!                                data_frame(ii,jj,0)=data_frame(ii,jj,0)+dvol*uold(ind_cell(i),1)*temp !mass weighted temperature
!                              end if
      
! #ifdef SOLVERmhd
!                              if (movie_vars(NVAR+4).eq.1)then
!                                      data_frame(ii,jj,NVAR+4)=data_frame(ii,jj,NVAR+4)+ dvol*0.125*(&
!                                          uold(ind_cell(i),6)**2 + uold(ind_cell(i),7)**2 + uold(ind_cell(i),8)**2 &
!                                          + uold(ind_cell(i),NVAR+1)**2 + uold(ind_cell(i),NVAR+2)**2 + uold(ind_cell(i),NVAR+3)**2)
!                              end if
! #endif
!                           endif
!                        end do
!                     end do
!                  end if
!               end do
   
!            end do
!            ! End loop over cells
   
!         end do
!         ! End loop over grids
!      end do
!   ! End loop over levels
!   end if

!   ! Loop over particles
!   do j=1,npartmax

! #if NDIM>2                 
!      xpf  = xp(j,1)-boxlen/2.0
!      ypf  = xp(j,2)-boxlen/2.0
!      zpf  = xp(j,3)-boxlen/2.0
!      ! Projection
!      xtmp=cos(theta_cam)*xpf+sin(theta_cam)*ypf
!      ytmp=cos(theta_cam)*ypf-sin(theta_cam)*xpf
!      xpf=xtmp
!      ypf=ytmp
!      ytmp=cos(phi_cam)*ypf+sin(phi_cam)*zpf
!      ztmp=cos(phi_cam)*zpf-sin(phi_cam)*ypf

!      if(proj_axis(proj_ind:proj_ind).eq.'x')then
!        xpf  = ytmp
!        ypf  = ztmp
!        zpf  = xtmp
!      elseif(proj_axis(proj_ind:proj_ind).eq.'y')then
!        xpf  = xtmp
!        ypf  = ztmp
!        zpf  = ytmp
!      else
!        xpf  = xtmp
!        ypf  = ytmp
!        zpf  = ztmp
!      endif
!      if(perspective_camera(proj_ind))then
!         xpf  = xpf*focal_camera(proj_ind)/(dist_camera-zpf)
!         ypf  = ypf*focal_camera(proj_ind)/(dist_camera-zpf)
!      endif
!      xpf  = xpf+boxlen/2.0
!      ypf  = ypf+boxlen/2.0
!      zpf  = zpf+boxlen/2.0
     
!      if(    xpf.lt.xleft_frame.or.xpf.ge.xright_frame.or.&
!           & ypf.lt.yleft_frame.or.ypf.ge.yright_frame.or.&
!           & zpf.lt.zleft_frame.or.zpf.ge.zright_frame)cycle
! #else
!      xpf  = xp(j,1)
!      ypf  = xp(j,2)
!      xtmp=cos(theta_cam)*xpf+sin(theta_cam)*xpf
!      ytmp=cos(theta_cam)*ypf-sin(theta_cam)*ypf
!      xpf=xtmp
!      ypf=ytmp
     
!      if(    xpf.lt.xleft_frame.or.xpf.ge.xright_frame.or.&
!           & ypf.lt.yleft_frame.or.ypf.ge.yright_frame)cycle
! #endif
!      ! Compute map indices for the cell
!      ii = min(int((xpf-xleft_frame)/dx_frame)+1,nw_frame)
!      jj = min(int((ypf-yleft_frame)/dy_frame)+1,nh_frame)
     
!      ! Fill up map with projected mass
! #ifdef SOLVERmhd
!      if(star) then
!         if(tp(j).eq.0.) then
!            if(mass_cut_refine>0.0.and.zoom_only) then
!               if(mp(j)<mass_cut_refine) data_frame(ii,jj,NVAR+5)=data_frame(ii,jj,NVAR+5)+mp(j)
!            else
!               data_frame(ii,jj,NVAR+5)=data_frame(ii,jj,NVAR+5)+mp(j)
!            endif
!         else
!            data_frame(ii,jj,NVAR+6)=data_frame(ii,jj,NVAR+6)+mp(j)
!         endif
!      else
!         if(mass_cut_refine>0.0.and.zoom_only) then
!            if(mp(j)<mass_cut_refine) data_frame(ii,jj,NVAR+5)=data_frame(ii,jj,NVAR+5)+mp(j)
!         else
!            data_frame(ii,jj,NVAR+5)=data_frame(ii,jj,NVAR+5)+mp(j)
!         endif
!      endif
! #else
!      if(star) then
!         if(tp(j).eq.0.) then
!            if(mass_cut_refine>0.0.and.zoom_only) then
!               if(mp(j)<mass_cut_refine) data_frame(ii,jj,NVAR+1)=data_frame(ii,jj,NVAR+1)+mp(j)
!            else
!               data_frame(ii,jj,NVAR+1)=data_frame(ii,jj,NVAR+1)+mp(j)
!            endif
!         else
!            data_frame(ii,jj,NVAR+2)=data_frame(ii,jj,NVAR+2)+mp(j)
!         endif
!      else
!         if(mass_cut_refine>0.0.and.zoom_only) then
!            if(mp(j)<mass_cut_refine) data_frame(ii,jj,NVAR+1)=data_frame(ii,jj,NVAR+1)+mp(j)
!         else
!            data_frame(ii,jj,NVAR+1)=data_frame(ii,jj,NVAR+1)+mp(j)
!         endif
!      endif
! #endif
!   end do
!   ! End loop over particles

! #ifndef WITHOUTMPI
! #ifdef SOLVERmhd
!   allocate(data_frame_all(1:nw_frame,1:nh_frame,0:NVAR+6))
!   call MPI_ALLREDUCE(data_frame,data_frame_all,nw_frame*nh_frame*(NVAR+6+1),MPI_DOUBLE_PRECISION,MPI_SUM,MPI_COMM_WORLD,info)
! #else
!   allocate(data_frame_all(1:nw_frame,1:nh_frame,0:NVAR+2))
!   call MPI_ALLREDUCE(data_frame,data_frame_all,nw_frame*nh_frame*(NVAR+2+1),MPI_DOUBLE_PRECISION,MPI_SUM,MPI_COMM_WORLD,info)
! #endif
!   allocate(dens_all(1:nw_frame,1:nh_frame))
!   call MPI_ALLREDUCE(dens,dens_all,nw_frame*nh_frame,MPI_DOUBLE_PRECISION,MPI_SUM,MPI_COMM_WORLD,info)
!   allocate(vol_all(1:nw_frame,1:nh_frame))
!   call MPI_ALLREDUCE(vol,vol_all,nw_frame*nh_frame,MPI_DOUBLE_PRECISION,MPI_SUM,MPI_COMM_WORLD,info)
!   data_frame=data_frame_all
!   dens=dens_all
!   vol=vol_all
!   deallocate(data_frame_all)
!   deallocate(dens_all)
!   deallocate(vol_all)
! #ifdef RT
!   if(rt) then
!      allocate(rt_data_frame_all(1:nw_frame,1:nh_frame,1:NGROUPS))
!      rt_data_frame_all(:,:,:)=0d0
!      call MPI_ALLREDUCE(rt_data_frame,rt_data_frame_all        &
!           ,nw_frame*nh_frame*NGROUPS,MPI_DOUBLE_PRECISION      &
!           ,MPI_SUM,MPI_COMM_WORLD,info)
!      rt_data_frame=rt_data_frame_all
!      deallocate(rt_data_frame_all)
!   endif
! #endif
! #endif
!   ! Convert into mass weighted                                                                                                         
!   do ii=1,nw_frame
!     do jj=1,nh_frame
! #ifdef SOLVERmhd
!       do kk=0,5
!         if(movie_vars(kk).eq.1) data_frame(ii,jj,kk)=data_frame(ii,jj,kk)/dens(ii,jj)
!       end do
!       do kk=6,8
!         if(movie_vars(kk).eq.1) data_frame(ii,jj,kk)=data_frame(ii,jj,kk)/vol(ii,jj)
!       end do
!       do kk=9,NVAR
!         if(movie_vars(kk).eq.1) data_frame(ii,jj,kk)=data_frame(ii,jj,kk)/dens(ii,jj)
!       end do
!       do kk=NVAR+1,NVAR+4
!         if(movie_vars(kk).eq.1) data_frame(ii,jj,kk)=data_frame(ii,jj,kk)/vol(ii,jj)
!       end do
! #else
!       do kk=0,NVAR
!         if(movie_vars(kk).eq.1) data_frame(ii,jj,kk)=data_frame(ii,jj,kk)/max(dens(ii,jj),smallr)
!       end do
! #endif
! #ifdef RT
!       if(rt) then
!          do kk=1,NGROUPS
!             if(rt_movie_vars(kk).eq.1) &
!                  rt_data_frame(ii,jj,kk)=rt_data_frame(ii,jj,kk)/dens(ii,jj)
!          end do
!       endif
! #endif

!     end do
!   end do
!   deallocate(dens)
!   deallocate(vol)

!   if(myid==1)then
!      ilun=10
!      allocate(data_single(1:nw_frame,1:nh_frame))
!      ! Output mass weighted density
! #ifdef SOLVERmhd
!      do kk=0, NVAR+6
! #else
!      do kk=0, NVAR+2
! #endif
!        if (movie_vars(kk).eq.1)then
!          open(ilun,file=TRIM(moviefiles(kk)),form='unformatted')
!          data_single=data_frame(:,:,kk)
!          rewind(ilun)  
!          if(tendmov>0)then
!             write(ilun)t,delx,dely,delz
!          else
!             write(ilun)aexp,delx,dely,delz
!          endif
!          write(ilun)nw_frame,nh_frame
!          write(ilun)data_single
!          close(ilun)
!        end if
!      end do

! #ifdef RT
!       if(rt) then
!          do kk=1, NGROUPS
!             if (rt_movie_vars(kk).eq.1) then
!                open(ilun,file=TRIM(rt_moviefiles(kk)),form='unformatted')
!                data_single(:,:)=0.
!                data_single=rt_data_frame(:,:,kk)
!                rewind(ilun)  
!                if(tendmov>0)then
!                   write(ilun)t,delx,dely,delz
!                else
!                   write(ilun)aexp,delx,dely,delz
!                endif
!                write(ilun)nw_frame,nh_frame
!                write(ilun)data_single
!                close(ilun)
!             end if
!          end do
!       endif
! #endif
     
!      deallocate(data_single)
!   endif

!   deallocate(data_frame)
! #ifdef RT
!   if(rt) deallocate(rt_data_frame)
! #endif
! #endif
!   ! Update counter
!   if(proj_ind.eq.len(trim(proj_axis))) then 
!      ! Increase counter and skip frames if timestep is large
!      imov=imov+1
!      do while((amovout(imov)<aexp.or.tmovout(imov)<t).and.(imov.lt.imovout))
!         imov=imov+1
!      end do
!   endif

!   nw_frame = nw_temp
!   nh_frame = nh_temp
!  enddo
end subroutine output_frame

subroutine set_movie_vars()
  use amr_commons
  ! This routine sets the movie vars from textual form
  integer::ll
  character(LEN=5)::dummy

  if(ANY(movie_vars_txt=='temp ')) movie_vars(0)=1
  if(ANY(movie_vars_txt=='dens ')) movie_vars(1)=1
  if(ANY(movie_vars_txt=='vx   ')) movie_vars(2)=1
  if(ANY(movie_vars_txt=='vy   ')) movie_vars(3)=1
#if NDIM>2
  if(ANY(movie_vars_txt=='vz   ')) movie_vars(4)=1
#endif
#if NDIM==2
  if(ANY(movie_vars_txt=='pres ')) movie_vars(4)=1
#endif
#if NDIM>2
  if(ANY(movie_vars_txt=='pres ')) movie_vars(5)=1
#endif
#if NVAR>5
  do ll=6,NVAR
    write(dummy,'(I3.1)') ll
    if(ANY(movie_vars_txt=='var'//trim(adjustl(dummy))//' ')) movie_vars(ll)=1
 end do
#endif
#ifdef SOLVERmhd
  if(ANY(movie_vars_txt=='bxl  ')) movie_vars(6)=1
  if(ANY(movie_vars_txt=='byl  ')) movie_vars(7)=1
  if(ANY(movie_vars_txt=='bzl  ')) movie_vars(8)=1
  if(ANY(movie_vars_txt=='bxr  ')) movie_vars(NVAR+1)=1
  if(ANY(movie_vars_txt=='byr  ')) movie_vars(NVAR+2)=1
  if(ANY(movie_vars_txt=='bzr  ')) movie_vars(NVAR+3)=1
  if(ANY(movie_vars_txt=='pmag ')) movie_vars(NVAR+4)=1
  if(ANY(movie_vars_txt=='dm   ')) movie_vars(NVAR+5)=1
  if(ANY(movie_vars_txt=='stars')) movie_vars(NVAR+6)=1
#else
  if(ANY(movie_vars_txt=='dm   ')) movie_vars(NVAR+1)=1
  if(ANY(movie_vars_txt=='stars')) movie_vars(NVAR+2)=1
#endif
end subroutine set_movie_vars
