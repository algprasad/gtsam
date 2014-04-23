function [values, measurements] = covarianceAnalysisCreateTrajectory( options, metadata )
% Create a trajectory for running covariance analysis scripts.
% 'options' contains fields for including various factor types and setting trajectory length
% 'metadata' is a storage variable for miscellaneous factor-specific values
% Authors: Luca Carlone, David Jensen
% Date: 2014/04/16

import gtsam.*;

values = Values;

warning('fake angles! TODO: use constructor from roll-pitch-yaw when using real data - currently using identity rotation')

if options.useRealData == 1
  %% Create a ground truth trajectory from Real data (if available)
  fprintf('\nUsing real data as ground truth\n');
  gtScenario = load('truth_scen2.mat', 'Time', 'Lat', 'Lon', 'Alt', 'Roll', 'Pitch', 'Heading',...
    'VEast', 'VNorth', 'VUp');
  
  % Limit the trajectory length
  options.trajectoryLength = min([length(gtScenario.Lat) options.trajectoryLength]);
  fprintf('Scenario Ind: ');
  
  for i=0:options.trajectoryLength
    scenarioInd = options.subsampleStep * i + 1;
    fprintf('%d, ', scenarioInd);
    if (mod(i,12) == 0) fprintf('\n'); end
    
    %% Generate the current pose
    currentPoseKey = symbol('x', i);
    currentPose = imuSimulator.getPoseFromGtScenario(gtScenario,scenarioInd);
    % add to values
    values.insert(currentPoseKey, currentPose);
    
    %% gt Between measurements
    if options.includeBetweenFactors == 1 && i > 0
      prevPose = values.at(currentPoseKey - 1);
      deltaPose = prevPose.between(currentPose);
      measurements(i).deltaVector = Pose3.Logmap(deltaPose);
    end
    
    %% gt IMU measurements
    if options.includeIMUFactors == 1
      currentVelKey = symbol('v', i);
      currentBiasKey = symbol('b', i);
      deltaT = 0.01;   % amount of time between IMU measurements
      if i == 0
        currentVel = [0 0 0]';
      else
        % integrate & store intermediate measurements       
        for j=1:options.subsampleStep % we integrate all the intermediate measurements
          previousScenarioInd = options.subsampleStep * (i-1) + 1;
          scenarioIndIMU1 = previousScenarioInd+j-1;
          scenarioIndIMU2 = previousScenarioInd+j;
          IMUPose1 = imuSimulator.getPoseFromGtScenario(gtScenario,scenarioIndIMU1);
          IMUPose2 = imuSimulator.getPoseFromGtScenario(gtScenario,scenarioIndIMU2);
          IMURot2 = IMUPose2.rotation.matrix;
                    
          IMUdeltaPose = IMUPose1.between(IMUPose2);
          IMUdeltaPoseVector     = Pose3.Logmap(IMUdeltaPose);
          IMUdeltaRotVector      = IMUdeltaPoseVector(1:3);
          IMUdeltaPositionVector = IMUPose2.translation.vector - IMUPose1.translation.vector; % translation in absolute frame
          
          measurements(i).imu(j).deltaT = deltaT;
          
          % gyro rate: Logmap(R_i' * R_i+1) / deltaT
          measurements(i).imu(j).gyro = IMUdeltaRotVector./deltaT;
          
          % deltaPij += deltaVij * deltaT + 0.5 * deltaRij.matrix() * biasHat.correctAccelerometer(measuredAcc) * deltaT*deltaT;
          % acc = (deltaPosition - initialVel * dT) * (2/dt^2)
          measurements(i).imu(j).accel = IMURot2' * (IMUdeltaPositionVector - currentVel.*deltaT).*(2/(deltaT*deltaT));
          
          % Update velocity
          currentVel = currentVel + IMURot2 * measurements(i).imu(j).accel * deltaT;
        end
      end
      
      % Add Values: velocity and bias
      values.insert(currentVelKey, LieVector(currentVel));
      values.insert(currentBiasKey, metadata.imu.zeroBias);
    end
    
    %% gt GPS measurements
    if options.includeGPSFactors == 1 && i > 0
      gpsPosition = imuSimulator.getPoseFromGtScenario(gtScenario,scenarioInd).translation.vector;
      measurements(i).gpsPosition = Point3(gpsPosition);
    end
    
  end
  fprintf('\n');
else
  error('Please use RealData')
  %% Create a random trajectory as ground truth
  currentPose = Pose3; % initial pose  % initial pose
  
  unsmooth_DP = 0.5; % controls smoothness on translation norm
  unsmooth_DR = 0.1; % controls smoothness on rotation norm
  
  fprintf('\nCreating a random ground truth trajectory\n');
  currentPoseKey = symbol('x', 0);
  values.insert(currentPoseKey, currentPose);
  
  for i=1:options.trajectoryLength
    % Update the pose key
    currentPoseKey = symbol('x', i);
    
    % Generate the new measurements
    gtDeltaPosition = unsmooth_DP*randn(3,1) + [20;0;0]; % create random vector with mean = [20 0 0]
    gtDeltaRotation = unsmooth_DR*randn(3,1) + [0;0;0]; % create random rotation with mean [0 0 0]
    measurements.deltaMatrix(i,:) = [gtDeltaRotation; gtDeltaPosition];
    
    % Create the next pose
    deltaPose = Pose3.Expmap(measurements.deltaMatrix(i,:)');
    currentPose = currentPose.compose(deltaPose);
    
    % Add the current pose as a value
    values.insert(currentPoseKey, currentPose);
  end  % end of random trajectory creation
end % end of else

end % end of function
