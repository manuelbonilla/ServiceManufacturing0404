function [] = ManualArmAccuracyCheck(hgs)
% ManualArmAccuracyCheck Gui is used to collect ball-bar data for
% ball bar accuracy check
%
% Syntax:
%   ManualArmAccuracyCheck(hgs)
%       This will start  the user interface for tgs ballbar _accuracy check
%
% Notes:
%   This script requires the hgs_robot object as input argument, i.e. a
%   connection to robot must be established before running this script.
%
% See also:
%   bbar_collect_data.m
%
%
% $Author: dmoses $
% $Revision: 4098 $
% $Date: 2015-07-01 15:35:30 -0400 (Wed, 01 Jul 2015) $
% Copyright: MAKO Surgical Corp (2008)
%

% If no arguments are specified create a connection to the default
% hgs_robot
if nargin<1
    hgs = connectRobotGui;
    if isempty(hgs)
        return;
    end
end

% Checks for arguments if any
if (~isa(hgs,'hgs_robot'))
    error('Invalid argument: %s argument must be an hgs_robot object',...
        hgs);
end

%set gravity constants to Knee EE
comm(hgs,'set_gravity_constants','KNEE');
%Test Limit
rmsFailLimit=0.14;
rmsWarnLimit=0.105;
%initialize some variable
dataLength = 0;
computeBaseBall = false;
rmsValue = 0;
minDataLengthCalc = 20;
dataLengthCheck = 15;
ballLocation = 1;
startCollection = true;
EE_MotionCheckData = [];
stopAutoCollection = false;
waitForMotion = true;
angleUpdateTimer = [];
%ballbar data structure  initializations:

accuracyCheckData.lbb = 0;
accuracyCheckData.basePos = [];
accuracyCheckData.baseBall = [];
accuracyCheckData.data(1).location = [hgs.CALIB_BALL_A]';
accuracyCheckData.data(2).location = [hgs.CALIB_BALL_B]';
accuracyCheckData.data(3).location = [hgs.CALIB_BALL_C]';
accuracyCheckData.data(1).EE_ball_wrt_base = [];
accuracyCheckData.data(2).EE_ball_wrt_base = [];
accuracyCheckData.data(3).EE_ball_wrt_base = [];
%we assume there are only 3 calibration balls, but we try to look for the
%forth ball (ball D) in case there is 1.x or earlier version of 2.0 robot
try
    ball_D = [hgs.CALIB_BALL_D]';
catch
    ball_D = [];
end
if ~isempty(ball_D)
    accuracyCheckData.data(4).location = ball_D;
    accuracyCheckData.data(4).EE_ball_wrt_base = [];
    radialErr = cell(1,4);
else
    radialErr = cell(1,3);
end

% Setup Script Identifiers for generic GUI
scriptName = 'Arm Accuracy Check';

% Create generic Mako GUI
guiHandles = generateMakoGui(scriptName,[],hgs, 1);

set(guiHandles.figure,...
    'CloseRequestFcn',@closeCallBackFcn);

set(guiHandles.mainButtonInfo,'String',sprintf(['Click here to ' ...
    'accept your selection below and start ' ...
    'Arm accuracy check']), ...
    'FontSize',0.15, 'FontWeight','bold');

% Setup the main function
set(guiHandles.mainButtonInfo,'CallBack',@collectData);

%start robot enable procedure
userCancel=false;
try
    robotFrontPanelEnable(hgs,guiHandles);
catch
    if userCancel
        return;
    end
end

if(~userCancel)
    % Add axis for EE image
    guiHandles.axis = axes('parent', guiHandles.extraPanel, ...
        'XGrid','off','YGrid','off','box','off','visible','off');
    
    defaultColor = get( guiHandles.uiPanel, 'BackgroundColor');
    
    % Add initial UI components.
    guiHandles.calcBaseBall_S = uicontrol(guiHandles.uiPanel,...
        'Style','text',...
        'HorizontalAlignment', 'left', ...
        'Units','Normalized',...
        'BackgroundColor',defaultColor,...
        'FontWeight','bold',...
        'FontUnits','normalized',...
        'FontSize',0.8,...
        'SelectionHighlight','off',...
        'Position',[0.1 0.85 0.6 0.05],...
        'String', 'Compute Check Ball Location:');
    
    guiHandles.calcBaseBallPopUp = uicontrol(guiHandles.uiPanel,...
        'Style','popupmenu',...
        'Units','Normalized',...
        'FontWeight','bold',...
        'FontUnits','normalized',...
        'FontSize',1,...
        'SelectionHighlight','off',...
        'Position',[0.7 0.85 0.2 0.05],...
        'BackgroundColor','white',...
        'String', {'No', 'Yes'},...
        'Callback',@changeFocus,...
        'value', 1);
    
    commonProperties = struct(...
        'Style','text',...
        'HorizontalAlignment', 'left', ...
        'Units','Normalized',...
        'BackgroundColor',defaultColor,...
        'FontWeight','normal',...
        'FontUnits','normalized',...
        'FontSize',0.6,...
        'SelectionHighlight','off'...
        );
    guiHandles.CALEESerialNumberLabel = uicontrol(guiHandles.uiPanel,...
        commonProperties,...
        'Position',[0.1, 0.65 0.8 0.05],...
        'String','Calibration EE Serial Number');
    guiHandles.CALEESerialNumberText = uicontrol(guiHandles.uiPanel,...
        commonProperties,...
        'BackgroundColor','white',...
        'Position',[0.1, 0.55 0.8 0.1],...
        'String',hgs.CALEE_SERIAL_NUMBER);
    guiHandles.CALBARSerialNumberLabel = uicontrol(guiHandles.uiPanel,...
        commonProperties,...
        'Position',[0.1, 0.3 0.8 0.05],...
        'String','Calibration Bar Serial Number');
    guiHandles.CALBARSerialNumberText = uicontrol(guiHandles.uiPanel,...
        commonProperties,...
        'BackgroundColor','white',...
        'Position',[0.1, 0.2 0.8 0.1],...
        'String',hgs.CALBAR_SERIAL_NUMBER);
    
    guiHandles.EE_Ball =   uicontrol(guiHandles.extraPanel,...
        commonProperties,...
        'BackgroundColor', 'white',...
        'FontSize',0.7,...
        'Position',[0.1 0.85 0.8 0.1],...
        'String', 'Calib EE Ball: A',...
        'Visible','off');
    
    str = sprintf('Arm Configuration: %s','---');
    guiHandles.robotPoseText  =   uicontrol(guiHandles.uiPanel,...
        commonProperties,...
        'FontSize',0.8,...
        'FontWeight','bold',...
        'Position',[0.05 0.85 0.9 0.05],...
        'String', str,...
        'visible','off');
    
    guiHandles.baseB_Location  =   uicontrol(guiHandles.uiPanel,...
        commonProperties,...
        'Style','text',...
        'FontSize',1,...
        'Position',[0.05 0.8 0.6 0.025],...
        'String', '',...
        'visible', 'off' );
    str = sprintf('Ball-bar length [mm]: %3.3f',hgs.BALLBAR_LENGTH_1*1000);
    
    guiHandles.bbar_Length  =   uicontrol(guiHandles.uiPanel,...
        commonProperties,...
        'Style','text',...
        'FontSize',1,...
        'Position',[0.05 0.77 0.6 0.025],...
        'String',str,...
        'visible', 'off' );
    
    guiHandles.radial_err_S = uicontrol(guiHandles.uiPanel,...
        commonProperties,...
        'FontSize',0.8,...
        'Position',[0.05 0.6 0.6 0.1],...
        'BackgroundColor', defaultColor,...
        'String', sprintf('Radial error [mm]:'),...
        'Visible','off');
    
    guiHandles.radial_err_D = uicontrol(guiHandles.uiPanel,...
        commonProperties,...
        'HorizontalAlignment', 'Right', ...
        'FontSize',0.8,...
        'Position',[0.65 0.6 0.3 0.1],...
        'String', sprintf('%6.3f', 0),...
        'visible', 'off');
    
    guiHandles.RMS_S = uicontrol(guiHandles.uiPanel,...
        commonProperties,...
        'FontSize',0.8,...
        'Position',[0.05 0.5 0.45 0.1],...
        'String', sprintf('RMS [mm]:'),...
        'visible', 'off' );
    guiHandles.RMS_D = uicontrol(guiHandles.uiPanel,...
        commonProperties,...
        'HorizontalAlignment', 'Right', ...
        'FontSize',0.8,...
        'Position',[0.5 0.5 0.45 0.1],...
        'String','---',...
        'visible', 'off' );
    
    guiHandles.jointAngles_S =  uicontrol(guiHandles.uiPanel,...
        'Style','text',...
        'Units','Normalized',...
        'HorizontalAlignment', 'Left', ...
        'BackgroundColor', defaultColor,...
        'FontWeight','bold',...
        'FontUnits','normalized',...
        'FontSize',0.4,...
        'Position',[0.0,0.25 0.8 0.1],...
        'String', 'Current joint angles [rad]',...
        'visible', 'off' );
    guiHandles.eraseAllBtn = uicontrol(guiHandles.uiPanel,...
        'Style','pushbutton',...
        'Units','Normalized',...
        'FontWeight','bold',...
        'FontUnits','normalized',...
        'FontSize',0.4,...
        'SelectionHighlight','off',...
        'Position',[0, 0.08, 0.32 0.07],...
        'BackgroundColor',defaultColor,...
        'String', 'Clear All Poses', ...
        'Callback',@eraseAll,...
        'Enable','off',...
        'visible', 'off');
    
    
    guiHandles.eraseBtn = uicontrol(guiHandles.uiPanel,...
        'Style','pushbutton',...
        'Units','Normalized',...
        'FontWeight','bold',...
        'FontUnits','normalized',...
        'FontSize',0.4,...
        'SelectionHighlight','off',...
        'Position',[0.33, 0.08, 0.32 0.07],...
        'BackgroundColor',defaultColor,...
        'Callback',@erasePose,...
        'String', 'Erase Pose', ...
        'Enable','off',...
        'visible', 'off');
    
    guiHandles.getDataBtn = uicontrol(guiHandles.uiPanel,...
        'Style','pushbutton',...
        'Units','Normalized',...
        'FontWeight','bold',...
        'FontUnits','normalized',...
        'FontSize',0.4,...
        'SelectionHighlight','off',...
        'Position',[0.66, 0.08, 0.32 0.07],...
        'BackgroundColor',defaultColor,...
        'Callback',@collectData,...
        'String', 'Record Pose', ...
        'Enable','off',...
        'visible', 'off');
    
    guiHandles.calc_check_ball = uicontrol(guiHandles.uiPanel,...
        'Style','pushbutton',...
        'HorizontalAlignment', 'Left', ...
        'Units','Normalized',...
        'FontWeight','bold',...
        'FontUnits','normalized',...
        'FontSize',0.4,...
        'SelectionHighlight','off',...
        'Position',[0.0, 0.0, 0.45 0.07],...
        'BackgroundColor',defaultColor,...
        'Callback',@calcCheckBall,...
        'String', 'Calculate Check Ball', ...
        'Enable','off',...
        'visible', 'off');
    
    guiHandles.writeToFileBtn = uicontrol(guiHandles.uiPanel,...
        'Style','pushbutton',...
        'Units','Normalized',...
        'HorizontalAlignment', 'Right', ...
        'FontWeight','bold',...
        'FontUnits','normalized',...
        'FontSize',0.4,...
        'SelectionHighlight','off',...
        'Position',[0.55, 0.0, 0.45 0.07],...
        'BackgroundColor',defaultColor,...
        'Callback',@writeToFile,...
        'String', 'Save Check Ball', ...
        'Enable','off',...
        'visible', 'off');
    
end
    function collectData(varargin)
        %check if homing done
        if ~homingDone(hgs)
            presentMakoResults(guiHandles,'FAILURE','Homing Not Done');
            log_message(hgs,'Arm Accuracy Check failed (Homing not done)',...
                'ERROR');
            return;
        end
        set(guiHandles.mainButtonInfo,...
            'FontSize',0.3 );
        if dataLength == 0
            %update info about robot's lefty/righty configuration
            %based on J3 joint angle.
            if hgs.joint_angles(3) < 0
                set(guiHandles.robotPoseText,'String', ['Arm ' ...
                    'Configuration: RIGHTY']);
                accuracyCheckData.basePos = hgs.BASEBALL_RIGHT_CHECK';
                accuracyCheckData.baseBall = 'BASEBALL_RIGHT_CHECK';
            else
                set(guiHandles.robotPoseText,'String', ['Arm ' ...
                    'Configuration: LEFTY']);
                accuracyCheckData.basePos = hgs.BASEBALL_LEFT_CHECK';
                accuracyCheckData.baseBall = 'BASEBALL_LEFT_CHECK';
            end
            
            str = sprintf('Base ball location [mm]: %s',...
                sprintf('  %3.2f', accuracyCheckData.basePos' * 1000));
            set(guiHandles.baseB_Location,'String', str);
        end
        
        if  startCollection == true,
            log_message(hgs,'Arm Accuracy Check started.');
            startCollection = false;
            hndls = [ guiHandles.calcBaseBall_S,...
                guiHandles.calcBaseBallPopUp,...
                guiHandles.CALEESerialNumberLabel,...
                guiHandles.CALEESerialNumberText,...
                guiHandles.CALBARSerialNumberLabel,...
                guiHandles.CALBARSerialNumberText,...
                ];
            set(hndls, 'Enable','off', 'visible','off');
            
            hndls = [ guiHandles.robotPoseText,...
                guiHandles.EE_Ball, guiHandles.baseB_Location , ...
                guiHandles.bbar_Length,  guiHandles.radial_err_S, ...
                guiHandles.radial_err_D, ...
                guiHandles.RMS_S, guiHandles.RMS_D,  ...
                guiHandles.eraseBtn, ...
                guiHandles.getDataBtn, ...
                guiHandles.eraseAllBtn, ...
                ];
            set(hndls, 'visible','on', 'Enable', 'on');
            %Remove/disable calculate base ball button depending on
            %which mode we are in.
            if get(guiHandles.calcBaseBallPopUp,'Value') == 1
                set( guiHandles.calc_check_ball,...
                    'visible','off', 'Enable', 'off');
                computeBaseBall = false;
            else
                set( guiHandles.calc_check_ball,...
                    'visible','on', 'Enable', 'off');
                computeBaseBall = true;
            end
            
            
            set(guiHandles.eraseBtn,'Enable', 'off');
            set(guiHandles.eraseAllBtn,'Enable', 'off');
            set(guiHandles.extraPanel,'BackgroundColor','white');
            accuracyCheckData.lbb = hgs.BALLBAR_LENGTH_1;
            
            str = sprintf('Ball-bar length [mm]: %s',...
                sprintf('  %3.3f', ...
                accuracyCheckData.lbb*1000));
            set(guiHandles.bbar_Length,'string',str);
            showCallEE();
            drawnow;
            str = sprintf('Base ball location [mm]: %s',...
                sprintf('  %3.3f', accuracyCheckData.basePos' * 1000));
            set(guiHandles.baseB_Location,'String', str);
            str = sprintf('Distance to previous base ball location [mm] %3.2f',0);
            set(guiHandles.baseB_Location,'TooltipString', str);
            %create a timer object to shown joint angles
            angleUpdateTimer = timer(...
                'TimerFcn',@updateAnglesAndError,...
                'Period',0.15,...
                'ObjectVisibility','off',...
                'BusyMode','drop',...
                'ExecutionMode','fixedSpacing'...
                );
            
            %finally switch to gravity mode:
            %mode(hgs,'home_mako');
            mode(hgs,'zerogravity','ia_hold_enable',0);
            
            pause(0.5);
            %start timer
            start(angleUpdateTimer)
            
        else
            [joint_angles, flange_tx] = get(hgs,'joint_angles','flange_tx');
            
            flange_tx = reshape(flange_tx,4,4)';
            EE_ballPos_wrt_base = flange_tx(1:3, 1:3) * ...
                accuracyCheckData.data(ballLocation).location + flange_tx(1:3,4);
            accuracyCheckData.data(ballLocation).EE_ball_wrt_base = ...
                [accuracyCheckData.data(ballLocation).EE_ball_wrt_base, ...
                EE_ballPos_wrt_base];
            %compute radial error
            currentRadialErr = computeRadialErr( EE_ballPos_wrt_base );
            radialErr{ballLocation}  = [radialErr{ballLocation}; ...
                currentRadialErr];
            %update RMS
            updateRMS;
            dataLength = size(accuracyCheckData.data(ballLocation).EE_ball_wrt_base,2);
        end
        updateMainButtonInfo(guiHandles,'text', ...
            sprintf('Number of Poses: %d', dataLength ));
        if (dataLength >0)
            set(guiHandles.eraseBtn,'Enable', 'on');
            set(guiHandles.eraseAllBtn,'Enable', 'on');
        end
        if computeBaseBall == true
            if(dataLength >= minDataLengthCalc)
                set(guiHandles.calc_check_ball,'Enable', 'on');
            else
                set(guiHandles.calc_check_ball,'Enable', 'off');
            end
        else
            if(dataLength == dataLengthCheck )
                fileName =[sprintf('ArmAccuracyCheck-%s-data',hgs.name),...
                    datestr(now,'yyyy-mm-dd-HH-MM')];
                fullFileName=fullfile(guiHandles.reportsDir,fileName);
                save(fullFileName, 'accuracyCheckData');
                if (rmsValue <= rmsWarnLimit),
                    presentMakoResults(guiHandles,'SUCCESS');
                    log_message(hgs,sprintf(['Ball-bar Accuracy Check successful ',...
                        '(RMS Err %4.3f mm)'],rmsValue));
                    
                elseif rmsValue > rmsWarnLimit && rmsValue <= rmsFailLimit
                    presentMakoResults(guiHandles,'WARNING',...
		    	sprintf('RMS Error = %4.3f mm\nLimit %4.3f mm',rmsValue,rmsFailLimit));
                    log_message(hgs,sprintf(['Ball-bar Accuracy Check marginally successful ',...
                        '(RMS Err %4.3f mm)'],rmsValue));
                    
                else
                    resultStr{1} = sprintf('RMS = %6.3fmm (Max %1.2fmm)', rmsValue,rmsFailLimit);
                    presentMakoResults(guiHandles,'FAILURE', resultStr);
                    log_message(hgs,sprintf(['Ball-bar Accuracy Check failed ',...
                        '(RMS Err %4.3f mm)'],rmsValue),'ERROR');
                end
                stopAutoCollection = true;
                %set arm to free mode
                mode(hgs,'zerogravity');
            end
        end
    end
%------------------------------------------------------------------------------
% Callback function to erase last recorded pose.
%------------------------------------------------------------------------------
    function  erasePose(varargin)
        dataLength = size(accuracyCheckData.data(ballLocation).EE_ball_wrt_base,2);
        %if there are data available clear the last data;
        if dataLength > 0
            accuracyCheckData.data(ballLocation).EE_ball_wrt_base(:,dataLength) = [];
            radialErr{ballLocation}(end) = [];
            dataLength = dataLength -1;
        end
        updateRMS;
        % disable button if there is no Data available
        if dataLength == 0
            set(guiHandles.eraseBtn,'Enable', 'off');
            set(guiHandles.eraseAllBtn,'Enable', 'off');
        end
        set(guiHandles.mainButtonInfo,'String',sprintf('Number of Poses: %d', ...
            dataLength));
        if(dataLength < minDataLengthCalc)
            set(guiHandles.calc_check_ball,'Enable', 'off');
        end
        waitForMotion = true;
    end
%------------------------------------------------------------------------------
% Callback function to erase All recorded poses.
%------------------------------------------------------------------------------
    function  eraseAll(varargin)
        set(guiHandles.mainButtonInfo,'String', 'Number of Poses: 0');
        accuracyCheckData.data(ballLocation).EE_ball_wrt_base = [];
        radialErr{ballLocation} = [];
        updateRMS;
        set(guiHandles.eraseBtn,'Enable', 'off');
        set(guiHandles.eraseAllBtn,'Enable', 'off');
        set(guiHandles.calc_check_ball,'Enable', 'off');
        dataLength = size(accuracyCheckData.data(ballLocation).EE_ball_wrt_base,2);
        waitForMotion = true;
    end
%------------------------------------------------------------------------------
% Callback function to write collected data to file
%------------------------------------------------------------------------------
    function  success = writeToFile(varargin)
        % check if there is a specific directory specified for all the reports
        % this is specified by MAKO_REPORTS_DIR environment variable
        % if not specified on windows use the desktop directory and on linux use
        % the tmp directory
        try
            switch accuracyCheckData.baseBall
                case {'BASEBALL_LEFT_CHECK'}
                    hgs.BASEBALL_LEFT_CHECK = accuracyCheckData.basePos';
                    success = true;
                case {'BASEBALL_RIGHT_CHECK'}
                    hgs.BASEBALL_RIGHT_CHECK = accuracyCheckData.basePos';
                    success = true;
                otherwise
                    errordlg('Invalid Check Base Ball')
                    success = false;
            end
        catch
            success = false;
        end
    end
%------------------------------------------------------------------------------
% Internal function to show the emage of the current calibration EE ball
%------------------------------------------------------------------------------
    function showCallEE()
        EE_BallString = {'Calib EE Ball: A',...
            'Calib EE Ball: B',...
            'Calib EE Ball: C',...
            'Calib EE Ball: D'};
        
        % if only 3 calibration balls available we assume new calibaration EE
        if size(accuracyCheckData.data,2) == 3,
            imageEE = {'eeBall_2_0_A.jpg','eeBall_2_0_B.jpg', ...
                'eeBall_2_0_C.jpg'};
        else
            imageEE = {'eeball_A.jpg', 'eeball_B.jpg', 'eeball_C.jpg', ...
                'eeball_D.jpg'};
        end
        imageFile = fullfile('robot_images',imageEE{ballLocation});
        set(guiHandles.EE_Ball, 'string', ...
            EE_BallString{ballLocation});
        eeImg = imread(imageFile);
        set(guiHandles.axis, 'NextPlot', 'replace');
        image(eeImg,'parent', guiHandles.axis);
        axis (guiHandles.axis, 'off')
        axis (guiHandles.axis, 'image')
        drawnow;
    end


%------------------------------------------------------------------------------
% Update function for timer object
%------------------------------------------------------------------------------
    function []= updateAnglesAndError(varargin)
        %check if still in free mode, if not, return
        if  ~startCollection
            if ~strcmp(mode(hgs),'zerogravity')
                errorMsg=char(hgs.zerogravity.mode_error);
                presentMakoResults(guiHandles,'FAILURE',errorMsg);
                log_message(hgs,['Arm Accuracy Check failed ( ' errorMsg,')'],...
                    'ERROR');
                %dataLength=dataLengthCheck;
                stop(angleUpdateTimer);
                delete(angleUpdateTimer);
                return;
            end
        end
        [joint_angles, flange_tx] = get(hgs,'joint_angles','flange_tx');
        %compute radial error
        flange_tx = reshape(flange_tx,4,4)';
        EE_ballPos_wrt_base = flange_tx(1:3, 1:3) * ...
            accuracyCheckData.data(ballLocation).location + ...
            flange_tx(1:3,4);
        %compute radial error
        currentRadialErr = computeRadialErr( EE_ballPos_wrt_base );
        set(guiHandles.radial_err_D, 'String', ...
            sprintf('%6.3f', currentRadialErr*1000));
        
        if dataLength == 0
            %update info about robot's lefty/righty configuration
            %based on J3 joint angle (Only if no data is collected.)
            if hgs.joint_angles(3) < 0
                set(guiHandles.robotPoseText,'String', ['Arm ' ...
                    'Configuration: RIGHTY']);
                accuracyCheckData.basePos = hgs.BASEBALL_RIGHT_CHECK';
                accuracyCheckData.baseBall = 'BASEBALL_RIGHT_CHECK';
            else
                set(guiHandles.robotPoseText,'String', ['Arm ' ...
                    'Configuration: LEFTY']);
                accuracyCheckData.basePos = hgs.BASEBALL_LEFT_CHECK';
                accuracyCheckData.baseBall = 'BASEBALL_LEFT_CHECK';
            end
            
            str = sprintf('Base ball location [mm]: %s',...
                sprintf('  %3.2f', accuracyCheckData.basePos' * 1000));
            set(guiHandles.baseB_Location,'String', str);
        end
        drawnow;
        
        if stopAutoCollection
            return;
        end
        if waitForMotion
            if sum(abs(hgs.joint_velocity)) > 1.0
                waitForMotion = false;
            end
            return;
        end
        %we need 3 set of EE position to check for motion
        if(size(EE_MotionCheckData,2) < 3)
            EE_MotionCheckData = [ EE_MotionCheckData,...
                EE_ballPos_wrt_base];
        else
            if norm(std(EE_MotionCheckData,0,2)) < 0.002 %less than 2mm
                %change in
                if dataLength == 0
                    % collect first point w/o check
                    collectData;
                    EE_MotionCheckData = [];
                    return;
                end
                dist = sqrt(sum((...
                    accuracyCheckData.data(ballLocation).EE_ball_wrt_base - ...
                    EE_ballPos_wrt_base(:,ones(1,dataLength))).^2));
                %if the new point is more than 5cm form all the
                %collected points then collect this point
                if all(dist > 0.05)
                    collectData;
                    EE_MotionCheckData = [];
                else
                    %ask to change position;
                    EE_MotionCheckData = [];
                end
            else
                EE_MotionCheckData = [];
            end
        end
    end

%------------------------------------------------------------------------------
% This Internal function computes radial error
%------------------------------------------------------------------------------
    function rdlErr = computeRadialErr(EE_ballPos_wrt_base)
        rdlErr =  norm (EE_ballPos_wrt_base -  accuracyCheckData.basePos) - ...
            accuracyCheckData.lbb;
    end
%------------------------------------------------------------------------------
% This Internal function computes RMS error
%------------------------------------------------------------------------------
    function [] = updateRMS()
        lgData = 0;
        sumSqr = 0;
        for k=1:size(radialErr,2)
            lgData =  lgData + length(radialErr{k});
            sumSqr = sumSqr + sum(radialErr{k}.^2) ;
        end
        if lgData > 0
            rmsValue = sqrt(sumSqr/lgData)*1000;
        else
            rmsValue = 0;
        end
        
        set(guiHandles.RMS_D, ...
            'String', sprintf('%6.3f', rmsValue) );
    end
%------------------------------------------------------------------------------
% This Internal function computes RMS error
%------------------------------------------------------------------------------
    function calcCheckBall(varargin)
        
        stopAutoCollection = true;
        [pfitArray, info, perf, jacobian] = sec_LM( 'accuracy_objfun', ...
            accuracyCheckData.basePos, ...
            [], [], ...
            accuracyCheckData.data(ballLocation).EE_ball_wrt_base, ...
            accuracyCheckData.lbb); %#ok<NASGU>
        pfit = pfitArray(:,end);
        oldBasePos = accuracyCheckData.basePos;
        accuracyCheckData.basePos = pfit;
        distFromPrevBasePos = norm(accuracyCheckData.basePos-oldBasePos);
        %update RMS based on the newlc calculated pose
        %compute radial error
        for i=1:size(accuracyCheckData.data(ballLocation).EE_ball_wrt_base,2)
            radialErr{ballLocation}(i,:)  = computeRadialErr( ...
                accuracyCheckData.data(ballLocation).EE_ball_wrt_base(:,i) );
        end
        updateRMS;
        %update pos
        str = sprintf('Base ball location [mm]: %s',...
            sprintf('  %3.2f', pfit'*1000));
        set(guiHandles.baseB_Location,'String', str);
        fileName =[sprintf('ArmAccuracyCheck-%s-data',hgs.name),...
            datestr(now,'yyyy-mm-dd-HH-MM')];
        fullFileName=fullfile(guiHandles.reportsDir,fileName);
        save(fullFileName, 'accuracyCheckData');
        if (rmsValue < rmsFailLimit),
            if writeToFile
	            if (rmsValue >= rmsWarnLimit)
		            presentMakoResults(guiHandles,'WARNING',...
                        sprintf('Check Ball Location Updated\nRMS = %4.3f mm\nLimit = %4.3f mm',rmsValue,rmsFailLimit));
                else
		            presentMakoResults(guiHandles,'SUCCESS',...
                        'Check Ball Location Updated');
		         end
            else
                presentMakoResults(guiHandles,'FAILURE',...
                    ['RMS acceptable but could not save ', ...
                    'results']);
            end
            
        else
            resultStr{1} = sprintf('RMS = %6.3fmm (Maximum %1.2fmm)', rmsValue,rmsFailLimit);
            presentMakoResults(guiHandles,'FAILURE', resultStr);
        end
        str = sprintf('Distance to previous base ball location [mm] %3.2f', ...
            distFromPrevBasePos * 1000);
        set(guiHandles.baseB_Location,'TooltipString', str);
    end

%------------------------------------------------------------------------------
% Call back function to close the gui
%------------------------------------------------------------------------------
    function changeFocus(varargin)
        uicontrol(guiHandles.mainButtonInfo);
    end
%------------------------------------------------------------------------------
% Call back function to close the gui
%------------------------------------------------------------------------------
    function closeCallBackFcn(varargin)
        %set arm to free mode
        mode(hgs,'zerogravity');
        
        %set userCancel flag to true
        userCancel=true;
        
        if  ~isempty(angleUpdateTimer)
            stop(angleUpdateTimer);
            delete(angleUpdateTimer);
        end
        closereq;
    end
end

% --------- END OF FILE ----------
