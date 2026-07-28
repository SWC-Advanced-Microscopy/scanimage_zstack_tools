function chalk(str,reset)
% Write erasable text to screen
%
% function chalk(str,reset)
%
% Purpose 
% Writes overwritable status messages to the command line. The
% caveat is that the messages will not work nicely if another 
% function writes to the command line as well. Runs a demo if
% no inputs provided
%
%
% Inputs
% str - string to print (add new line character if needed)
% reset - reset previous string length to zero
%
% Example
% chalk('',1)
% d={'hello','goodbye'}; 
% for ii=1:2; chalk(d{ii}), pause(2), end
% fprintf('\n') 
%
% Run without inputs for a demo
%
%
% Rob Campbell - July 2010



if nargin==0
    demo_chalk
    return
end

persistent previousStrLength ; 


if isempty(previousStrLength)
    previousStrLength=0;
end

if nargin==2 & reset==1
    previousStrLength=0;
end


%Wipe the previous string
if previousStrLength>0
    fprintf(repmat('\b',1,previousStrLength))
    fprintf(repmat(' ' ,1,previousStrLength))
    fprintf(repmat('\b',1,previousStrLength))
end



fprintf(str) %write the new string to screen

previousStrLength=length(str); %update the counter





% DEMO
function demo_chalk
    % Demo of the chalk function 
    %
    % function demo_chalk
    %
    % Rob Campbell - June 2010

    fprintf('\n  RUNNING DEMO\n\n')

    states={'finding chicken',...
            'arranging chicken',...
            'sorting eggs',...        
            'feeding',...        
            'more feeding',...        
            'cleaning poop',...        
            'Done!'};


    chalk('',1) %make sure chalk is reset

    for c=1:3
        fprintf('Hen %d: ', c)
        
        for ii=1:length(states)
            chalk(states{ii})
            pause(0.75)
        end
        fprintf('\n')
        chalk('',1) %reset chalk
    end

    
