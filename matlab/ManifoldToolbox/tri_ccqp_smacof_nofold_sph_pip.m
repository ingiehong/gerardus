function [con, bnd] = tri_ccqp_smacof_nofold_sph_pip(tri, R, vmin, vmax, isFree, y, feastol)
% TRI_CCQP_SMACOF_NOFOLD_SPH_PIP  Constraints in PIP format for CCQP-SMACOF
% to ensure that 2D triangules on the sphere preserve positive orientation.
%
% This function generates the linear, quadratic and cubic constraints that
% can be passed to cons_smacof_pip() to map a triangular mesh onto 2D
% without fold-overs or, equivalently, untangle a projection of a mesh on a
% sphere.
%
% [CON, BND] = tri_qcqp_smacof_nofold_2d_pip(TRI, R, VMIN, VMAX)
%
%   TRI is a 3-column matrix with a surface mesh triangulation. Each row
%   gives the indices of one triangle. The mesh needs to be a 2D manifold,
%   that can be embedded in 2D or 3D space. All triangles must be oriented
%   counter-clockwise (2D space) or with the normals pointing outwards (3D
%   space).
%
%   R is a scalar with the sphere radius.
%
%   VMIN, VMAX are the minimum and maximum volume allowed for each output
%   tetrahedron. If they are scalars, then the same value is used for all
%   tetrahedra. Otherwise, they must be column vectors, with one element
%   per tetrahedron in the mesh.
%
%   BND is a cell array with the variable bounds in PIP format. E.g.
%
%      BND = {'Bounds', ' -1 <= x1 <= 4', ' -1 <= y1 <= 2.5', ...
%             ' -1 <= x2 <= 4', ' -1 <= y2 <= 2.5'};
%
%   CON is a cell array with the problem constraints in PIP format. E.g.
%
%      CON = {'Subject to', ...
%            ' c1: -0.5 x6 y7 +0.5 x3 y7 +0.5 x7 y6 -0.5 x3 y6 -0.5 x7 y3 +0.5 x6 y3 >= 0.1'};
%
% ... = tri_qcqp_smacof_nofold_2d_pip(..., ISFREE, Y, FEASTOL)
%
%   ISFREE is an boolean N-vector, where N is the number of vertices in the
%   mesh. ISFREE(i)==true means that the i-th vertex is a free vertex (i.e.
%   an unknown in the QCQP problem). ISFREE(i)==false means that the i-th
%   vertex is a fixed vertex (i.e. with known constant coordinates). By
%   default, all vertices are assumed to be free.
%
%   Y is an (N, 3)-matrix that provides the coordinates of the fixed
%   vertices as Y(ISFREE, :). The values Y(~ISFREE, :) are simply ignored.
%   Thus, Y doesn't need to be provided if all vertices are free. If
%   there's at least a fixed vertex, then Y must be provided.
%
%   FEASTOL is an scalar with the feasibility tolerance for constraints in
%   SCIP. In SCIP, a constraint f(x) >= b is fulfilled when 
%   f(x) >= b-FEASTOL*max(1,|b|). This could lead to tetrahedra that
%   fulfill the VMIN constraint but have tiny negative volumes. To avoid
%   this and guarantee that SCIP will strictly fulfill the VMIN
%   constraints, this function turns them into 
%   f(x) >= VMIN+FEASTOL*max(1,|b|). Likewise, VMAX constraints become 
%   f(x) <= VMAX-FEASTOL*max(1,|b|). By default, FEASTOL=1e-6, but the user
%   can change this value in SCIP. In that case, the new value of FEASTOL
%   must be passed both to this function and to the function that runs the
%   SCIP solver.

% Author: Ramon Casero <rcasero@gmail.com>
% Copyright © 2014 University of Oxford
% Version: 0.2.5
%
% University of Oxford means the Chancellor, Masters and Scholars of
% the University of Oxford, having an administrative office at
% Wellington Square, Oxford OX1 2JD, UK. 
%
% This file is part of Gerardus.
%
% This program is free software: you can redistribute it and/or modify
% it under the terms of the GNU General Public License as published by
% the Free Software Foundation, either version 3 of the License, or
% (at your option) any later version.
%
% This program is distributed in the hope that it will be useful,
% but WITHOUT ANY WARRANTY; without even the implied warranty of
% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
% GNU General Public License for more details. The offer of this
% program under the terms of the License is subject to the License
% being interpreted in accordance with English Law and subject to any
% action against the University of Oxford being under the jurisdiction
% of the English Courts.
%
% You should have received a copy of the GNU General Public License
% along with this program.  If not, see
% <http://www.gnu.org/licenses/>.

% check arguments
narginchk(4, 7);
nargoutchk(0, 2);

%% Input arguments

if (size(tri, 2) ~= 3)
    error('TRI must have 3 columns')
end
if (~isscalar(R))
    error('R must be a scalar')
end

% number of vertices and triangles
N = max(tri(:));
Ntri = size(tri, 1);

if (isscalar(vmin))
    % same value for all tetrahedra
    vmin = vmin(ones(Ntri, 1));
end
if (isscalar(vmax))
    % same value for all tetrahedra
    vmax = vmax(ones(Ntri, 1));
end
if (size(vmin, 1) ~= Ntri)
    error('VMIN must be a scalar or a column vector with one element per triangle')
end
if (size(vmax, 1) ~= Ntri)
    error('VMAX must be a scalar or a column vector with one element per triangle')
end

if (nargin < 5 || isempty(isFree))
    % if the user doesn't specify which vertices are free and which ones
    % are fixed, we assume that all vertices are free
    isFree = true(N, 1);
end

% number of free vertices
Nfree = nnz(isFree);

if (~islogical(isFree) || ~isvector(isFree))
    error('ISFREE must be a vector of type logical (boolean)')
end

% convert to column vector
isFree = isFree(:);
if (length(isFree) ~= N)
    error('ISFREE must have one element per point in vertex in the mesh')
end

if (any(~isFree))
    
    if (nargin < 6)
        error('If any vertices are non-free, then initial configuration Y must be provided')
    end
    
    % check dimensions of initial configuration
    if ((size(y, 1) ~= N) || (size(y, 2) ~= 3))
        error('User says there is at least one fixed vertex, but initial configuration Y0 either has not been provided or has wrong dimensions')
    end
    
end

if (nargin < 7 || isempty(feastol))
    % feasibility tolerance for constraints in SCIP
    feastol = 1e-6;
end
if (feastol < 1e-9)
    error('SCIP will fail without warning when FEASTOL is too small. In particular, FEASTOL<numerics/epsilon (def 1e-9) will make FEASTOL=0')
end
if any(vmin < 10 * feastol)
    error('VMIN is too close to FEASTOL, and this may generate solutions with tiny negative areas/volumes. Scale your problem so that constraint limits can be larger')
end

%% Upper and lower bounds for the objective function variables

% init output
bnd = cell(1, 2*Nfree+1);
bnd{1} = 'Bounds';

% variables bounds, lb<=nu<=ub
idx = find(isFree);
for I = 1:Nfree

    % bounds for x-coordinate
    bnd{3*I-1} = sprintf(...
        ' %.15g <= x%d <= %.15g', ...
        -R, idx(I), R);

    % bounds for y-coordinate
    bnd{3*I} = sprintf(...
        ' %.15g <= y%d <= %.15g', ...
        -R, idx(I), R);
    
    % bounds for z-coordinate
    bnd{3*I+1} = sprintf(...
        ' %.15g <= z%d <= %.15g', ...
        -R, idx(I), R);
    
end

%% Tetrahedron constraints (each tetrahedron produces a constraint)

% find triangles that produce constraints (i.e. those with at least one
% free vertex)
idxtricon = find(sum(isFree(tri), 2) > 0)';
Ntricon = length(idxtricon);

% init output
con = cell(1, 2*Ntricon+1 + Nfree);
con{1} = 'Subject to';

count = 2; % index of the constraint element to fill up
for I = idxtricon
    
    % coordinates of the three vertices in the triangle
    triloc = tri(I, :);
    isFreeloc = isFree(triloc);
    
    % depending on the number of free vertices in the triangle, we create
    % different constraints
    switch (nnz(isFreeloc))
        
        case 0 % 0 free vertices, 3 fixed vertices
            
            % this case doesn't contribute any constraints to the quadratic
            % program, as the fixed vertices cannot be moved
            error('Assertion fail: This triangle has 3 fixed vertices and should have been skipped')
            
        case 1 % 1 free vertex, 2 fixed vertices
    
            % position of the free vertex
            idx = find(isFreeloc);
            
            % shift the vertices until the free vertex is the last one,
            % without changing the sign of the area
            yloc = y(triloc, :);
            yloc = circshift(yloc, 3 - idx);
            isFreeloc = circshift(isFreeloc, 3 - idx);
            if any(isFreeloc ~= [0 0 1]')
                error(['Assertion: Triangle ' num2str(I) ...
                    ' vertices cannot be shifted to canonic configuration'])
            end
            triloc = circshift(triloc(:), 3 - idx);
            
            % auxiliary variables to make the code more readable
            xi = yloc(1, 1); % x-coordinate of 1st fixed vertex
            yi = yloc(1, 2); % y-coordinate of 1st fixed vertex
            zi = yloc(1, 3); % z-coordinate of 1st fixed vertex
            xj = yloc(2, 1); % x-coordinate of 2nd fixed vertex
            yj = yloc(2, 2); % y-coordinate of 2nd fixed vertex
            zj = yloc(2, 3); % y-coordinate of 2nd fixed vertex
            
            k = triloc(3);   % index of free vertex in the mesh
            
            % constraint with lower bound. Example:
            % c1: -2 x1 +3.23 x4 +1 x2 * x3 >= -1
            if (vmin(I) > -inf)
                con{count} = sprintf( ...
                    ' c%d: %.15g x%d + %.15g y%d + %.15g z%d >= %.15g', ...
                    count-1, ...
                    (-yj*zi+yi*zj)/6, k, ...
                    (xj*zi-xi*zj)/6, k, ...
                    (-xj*yi+xi*yj)/6, k, ...
                    vmin(I) + feastol * max([1, abs(vmin(I))]));
                count = count + 1;
            end
            
            % constraint with upper bound. Example:
            % c1: -2 x1 +3.23 x4 +1 x2 * x3 <= 2
            if (vmax(I) < inf)
                con{count} = sprintf( ...
                    ' c%d: %.15g x%d + %.15g y%d + %.15g z%d <= %.15g', ...
                    count-1, ...
                    (-yj*zi+yi*zj)/6, k, ...
                    (xj*zi-xi*zj)/6, k, ...
                    (-xj*yi+xi*yj)/6, k, ...
                    vmax(I) - feastol * max([1, abs(vmax(I))]));
                count = count + 1;
            end
            
        case 2 % 2 free vertices, 1 fixed vertex
            
            % position of the fixed vertex
            idx = find(~isFreeloc);
            
            % shift the vertices until the fixed vertex is the first one,
            % without changing the sign of the area
            yloc = y(triloc, :);
            yloc = circshift(yloc, 1 - idx);
            isFreeloc = circshift(isFreeloc, 1 - idx);
            if any(isFreeloc ~= [0 1 1]')
                error(['Assertion: Triangle ' num2str(I) ...
                    ' vertices cannot be shifted to canonic configuration'])
            end
            triloc = circshift(triloc(:), 1 - idx);
            
            % auxiliary variables to make the code more readable
            xi = yloc(1, 1); % x-coordinate of fixed vertex
            yi = yloc(1, 2); % y-coordinate of fixed vertex
            zi = yloc(1, 3); % z-coordinate of fixed vertex
            
            j = triloc(2);   % index of free vertex in the mesh
            k = triloc(3);   % index of free vertex in the mesh

            % constraint with lower bound
            if (vmin(I) > -inf)
                con{count} = sprintf( ...
                    ' c%d: %.15g x%d y%d + %.15g x%d y%d + %.15g x%d z%d + %.15g y%d z%d + %.15g x%d z%d + %.15g y%d z%d >= %.15g', ...
                    count-1, ...
                    -zi/6, k, j, ...
                    zi/6, j, k, ...
                    yi/6, k, j, ...
                    -xi/6, k, j, ...
                    -yi/6, j, k, ...
                    xi/6, j, k, ...
                    vmin(I) + feastol * max([1, abs(vmin(I))]));
                count = count + 1;
            end
            
            % constraint with upper bound
            if (vmax(I) < inf)
                con{count} = sprintf( ...
                    ' c%d: %.15g x%d y%d + %.15g x%d y%d + %.15g x%d z%d + %.15g y%d z%d + %.15g x%d z%d + %.15g y%d z%d <= %.15g', ...
                    count-1, ...
                    -zi/6, k, j, ...
                    zi/6, j, k, ...
                    yi/6, k, j, ...
                    -xi/6, k, j, ...
                    -yi/6, j, k, ...
                    xi/6, j, k, ...
                    vmax(I) - feastol * max([1, abs(vmax(I))]));
                count = count + 1;
            end
            
        case 3 % three free vertices
            
            % auxiliary variables to make the code more readable

            i = triloc(1);   % index of free vertex in the mesh
            j = triloc(2);   % index of free vertex in the mesh
            k = triloc(3);   % index of free vertex in the mesh
            
            % constraint with lower bound
            if (vmin(I) > -inf)
                con{count} = sprintf( ...
                    ' c%d: %.15g x%d y%d z%d + %.15g x%d y%d z%d + %.15g x%d y%d z%d + %.15g x%d y%d z%d + %.15g x%d y%d z%d + %.15g x%d y%d z%d >= %.15g', ...
                    count-1, ...
                    -1/6, k, j, i, ...
                    1/6, j, k, i, ...
                    1/6, k, i, j, ...
                    -1/6, i, k, j, ...
                    -1/6, j, i, k, ...
                    1/6, i, j, k, ...
                    vmin(I) + feastol * max([1, abs(vmin(I))]));
                count = count + 1;
            end
            
            % constraint with upper bound
            if (vmax(I) < inf)
                con{count} = sprintf( ...
                    ' c%d: %.15g x%d y%d z%d + %.15g x%d y%d z%d + %.15g x%d y%d z%d + %.15g x%d y%d z%d + %.15g x%d y%d z%d + %.15g x%d y%d z%d <= %.15g', ...
                    count-1, ...
                    -1/6, k, j, i, ...
                    1/6, j, k, i, ...
                    1/6, k, i, j, ...
                    -1/6, i, k, j, ...
                    -1/6, j, i, k, ...
                    1/6, i, j, k, ...
                    vmax(I) - feastol * max([1, abs(vmax(I))]));
                count = count + 1;
            end
            
        otherwise
            
            error('Assertion error: Triangle has more than 3 vertices')
            
    end
    
end

% remove empty cells not used for constraints
con(count:end) = [];

%% Radius constraints

% add one radius constraint per free vertex
idx = find(isFree);
for I = 1:Nfree
    
    con{count} = sprintf( ...
        ' c%d: x%d^2 + y%d^2 + z%d^2 = %.15g', ...
        count, idx(I), idx(I), idx(I), R^2);
    count = count + 1;
    
end
