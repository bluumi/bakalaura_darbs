%% ---- BLIND DECONVOLUTION WITHOUT FFT CALCULATION ---

clear all
close all

%% VARIABLES (CAN CONVERT TO PROMPTS!)

shutter = 1/80;
h_dist = 2.3;   %% <-- To middle of road!
deg = 30;   %% <-- Parallel to road!
fov = 66;    %% <-- Camera lens FOV
c = 299792458;  %% <-- Speed of light, m/s
F0 = 24.125e9;  %% <-- IPM-165 source frequency
F_res = 8.932;  %% <-- STM32 ADC frequency resolution
cam_h = 0.85;

%% LOADING FILES

load canonParams.mat
image = imread('2020_05_31/M51.jpg');
fIDrec = fopen('2020_05_31-M5.txt');

%% CONVERTING FILE DATA
    %   IMAGE
[image, newOrigin] = undistortImage(image, cameraParams);
image=rgb2gray(image);
if length(image)>2000
    image = imresize(image, [NaN 2000]);
end

image = im2double(image);

px_hor = length(image); %% <-- Image pixels horizontally

    % STM32 OUTPUT
recData = textscan(fIDrec, '%s','delimiter','\n');
    recData = str2double(recData{1});
    recData = interp1(1:length(recData), recData, 1:1023)';
    maxVal = recData(1);
    recData(1) = 0;
    recData = recData(1:512);
    
%% CALCULATIONS

figure(1); imshow(image, []);
hold on;

axis equal
axis manual
rect = imrect('PositionConstraintFcn', @(x) [x(1) x(2) min(x(3),x(4))*[1 1]]);

p = getPosition(rect);
x = p(1,1);
y = p(1,2);
w = p(1,3);
h = p(1,4);

image_cutout = image(y+1:y+h, x+1:x+w, :);
    N = length(image_cutout);

image_cutout = image_cutout - mean(image_cutout(:));
    
hold off

[peaks, locs] = findpeaks(recData(2:512), 2:512, 'MinPeakHeight', maxVal/3);
loc = find(recData(1:512) == max(peaks));   % <-- Finds location of the highest peak after 
                                            %     the source peaks.

F_dop = loc*F_res; % <-- Doppler frequency calculation for located peak

speed = (F_dop*c)/(2*F0*cosd(deg)); % <-- Calculates speed received by radar, m/s

if h_dist == 0 || deg ==0
    motion_blur = 0;    % <-- Cosine error!
else
    dist_to_obj = (h_dist)/cosd(90-deg);    % <-- Approx. distance to object, m
    
    m_hor=(2*dist_to_obj*tand(fov/2));    % <-- Approx. distance in image plane, m
    
    vis_dist = 2*m_hor*cosd(deg);         % <-- Image plane turned so it's parallel to road,
                                          % <-- thus calculating approx. distance of travel, m
    
    m_px=vis_dist/px_hor;                 % <-- Meters per pixel (horizontally), m

    act_speed = speed*cosd(deg);          % <-- Actual speed of object, m/s
    travel = act_speed*shutter;           % <-- Traveled distance during one snapshot, m     

    motion_blur = travel/m_px;  % <-- Pixels traveled in image, px
    motion_blur = motion_blur*(2.1^(-2+(x+w/2)/500))-1;   % <-- Adding approx. exponential function
                                                        %     due to camera distortion

    LEN = round(motion_blur);   % <-- Approx. motion blur
end          

THETA = 180-round(atand(cam_h/(2*dist_to_obj))*(2.1^(-2+(x+w/2)/500))); % <-- 
%THETA = 179;
PSF = fspecial('motion',LEN,THETA);

cropped_image = imcrop(image, [x y w-1 h-1]);
cropped_image = edgetaper(cropped_image, PSF);

J = deconvlucy(cropped_image, PSF, 200, 10*sqrt(1e-9));
J = imadjust(J);

figure('Name', 'Result')
    subplot(121)
    imshow(cropped_image, []); title("Original image");
    
    subplot(122)
    imshow(medfilt2(J), []); title("Deconvoluted image")
