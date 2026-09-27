"""Independent EGM2008 check using SciPy normalized Legendre polynomials.

Run with Python + NumPy + SciPy >= 1.15. The normal MATLAB app does not
need Python. This computes a potential and finite difference gradient,
independently of the MATLAB recurrence and analytical derivatives.
"""
from pathlib import Path
import numpy as np, scipy.special as sp
from scipy.io import loadmat
m=loadmat(Path(__file__).resolve().parents[1] / 'data/gravity_egm2008_n180_coefficients.mat'); C=m['C']; S=m['S']; GM=float(m['GM'][0,0]); A=float(m['referenceRadius'][0,0]); N=int(m['degree'][0,0]); omega=7.292115e-5
f=1/298.257223563;e2=f*(2-f);a=6378137.
orders=np.arange(N+1)
norm=np.where(orders==0,np.sqrt(2.),2.)*(-1.)**orders
def V(r,phi,lam):
 p=sp.assoc_legendre_p_all(N,N,np.sin(phi),norm=True)[0,:,:N+1]*norm[None,:]
 modes=C*np.cos(orders*lam)[None,:]+S*np.sin(orders*lam)[None,:]
 q=np.sum((A/r)**np.arange(N+1)*np.sum(p*modes,axis=1))
 return GM/r*q + .5*omega**2*r*r*np.cos(phi)**2
for lat,lon,h in [(39.9042,116.4074,0),(0,0,0),(45,100,0),(80,-130,0),(-50,110,1000)]:
 ph=np.deg2rad(lat);la=np.deg2rad(lon);pr=a/np.sqrt(1-e2*np.sin(ph)**2);rho=(pr+h)*np.cos(ph);z=(pr*(1-e2)+h)*np.sin(ph);r=np.hypot(rho,z);ph=np.arctan2(z,rho)
 dr=10.;dp=1e-5;dl=1e-5
 ar=(V(r+dr,ph,la)-V(r-dr,ph,la))/(2*dr)
 ap=(V(r,ph+dp,la)-V(r,ph-dp,la))/((2*dp)*r)
 al=(V(r,ph,la+dl)-V(r,ph,la-dl))/(2*dl*r*np.cos(ph))
 print(lat,lon,h,np.sqrt(ar*ar+ap*ap+al*al),ar,ap,al)
