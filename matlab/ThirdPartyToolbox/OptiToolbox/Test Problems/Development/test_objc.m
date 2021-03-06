%% Test constant objective

P = coinRead('testQP.qps')

O = opti(P,optiset('solver','scip','display','iter'))
[x,f] = solve(O)
plot(O)

%% MILP2
clc
%Objective & Constraints
f = -[1 2 3 1]'; 
A = [-1 1 1 10; 1 -3 1 0]; 
b = [20;30];  
Aeq = [0 1 0 -3.5];
beq = 0;
%Setup Options
opts = optiset('solver','cbc','display','iter');
%Build & Solve
Opt = opti('grad',f,'ineq',A,b,'eq',Aeq,beq,'bounds',[0 0 0 2]',[40 inf inf 3]','int','CCCI','options',opts,'objbias',10)
[x,fval,exitflag,info] = solve(Opt)
plot(Opt)