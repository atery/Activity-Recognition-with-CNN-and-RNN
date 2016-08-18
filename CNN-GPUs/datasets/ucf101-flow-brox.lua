---------------------------------------------------------------
--  Activity-Recognition-with-CNN-and-RNN
--  https://github.com/chihyaoma/Activity-Recognition-with-CNN-and-RNN
-- 
-- 
--  Train a CNN on flow map of UCF-101 dataset 
-- 
-- 
--  Contact: Chih-Yao Ma at <cyma@gatech.edu>
---------------------------------------------------------------
--
--  Copyright (c) 2016, Facebook, Inc.
--  All rights reserved.
--
--  This source code is licensed under the BSD-style license found in the
--  LICENSE file in the root directory of this source tree. An additional grant
--  of patent rights can be found in the PATENTS file in the same directory.
--
--  UCF-101 flow maps dataset loader
--

local image = require 'image'
local paths = require 'paths'
local t = require 'datasets/transforms'
local ffi = require 'ffi'

local M = {}
local UCF101Dataset = torch.class('resnet.UCF101Dataset', M)

function UCF101Dataset:__init(imageInfo, opt, split)
   self.imageInfo = imageInfo[split] -- imagePath & imageClass
   self.opt = opt
   self.split = split
   self.dir = paths.concat(opt.data, split)
   assert(paths.dirp(self.dir), 'directory does not exist: ' .. self.dir)
end

function UCF101Dataset:get(i, nChannel, nStacking)
   local path = ffi.string(self.imageInfo.imagePath[i]:data()) -- e.g. Nunchucks/v_Nunchucks_g16_c03_flow_50.png
   local image

   -- extract frame number
   local afterPath = path:match("^.+flow(.+)$") -- e.g. _50.png
   local prePath = path:match("^.-flow")        -- e.g. Nunchucks/v_Nunchucks_g16_c03_flow
   local frameStr = afterPath:match("%d+")      -- e.g. 50
   local fileExten = afterPath:match("%a+")     -- e.g. png

   -- which frames will be stacked
   local frameStack = torch.range(frameStr-(nStacking-1), frameStr) -- e.g. 41~50

   -- read and stack images
   for i=1,frameStack:size(1) do
      path = prePath .. '_' .. frameStack[i] .. '.' .. fileExten
      local imageTmp = self:_loadImage(paths.concat(self.dir, path))
      imageTmp2 = imageTmp[{{3-(nChannel-1),3}}] -- the first channel is R
      if not image then
         image = imageTmp2
      else
         image = torch.cat(image, imageTmp2, 1) -- final dimension = 2*nStacking
      end
   end

   -- get image class as target
   local class = self.imageInfo.imageClass[i]

   return {
      input = image,
      target = class,
   }
end

function UCF101Dataset:_loadImage(path)
   local ok, input = pcall(function()
      return image.load(path, 3, 'float') -- RGB (R is 0)
   end)

   -- Sometimes image.load fails because the file extension does not match the
   -- image format. In that case, use image.decompress on a ByteTensor.
   if not ok then
      local f = io.open(path, 'r')
      assert(f, 'Error reading: ' .. tostring(path))
      local data = f:read('*a')
      f:close()

      local b = torch.ByteTensor(string.len(data))
      ffi.copy(b:data(), data, b:size(1))

      input = image.decompress(b, 3, 'float')
   end

   return input
end

function UCF101Dataset:size()
   return self.imageInfo.imageClass:size(1)
end


function UCF101Dataset:preprocess(opt)
   -- Computed from random subset of UCF-101 training Brox flow maps
   local dataFolder = paths.basename(self.opt.data)

   local meanstd = {}

   if dataFolder == 'FlowMap-Brox-frame' then
      meanstd = {mean = { 0.0091950063390791, 0.4922446721625, 0.49853131534726},
                  std = { 0.0056229398806939, 0.070845543666524, 0.081589332546496}}
   elseif dataFolder == 'FlowMap-Brox-crop40-frame' then
      meanstd = {mean = { 0.0091936888040752, 0.49204453841557, 0.49857498097595},
                  std = { 0.0056320802048129, 0.070939325098903, 0.081698516724234}}
   elseif dataFolder == 'FlowMap-Brox-crop20-frame' then
      meanstd = {mean = { 0.0092002901164412, 0.49243926742539, 0.49851170257907},
                  std = { 0.0056614266189997, 0.070921186231261, 0.081781848181796}}
   elseif dataFolder == 'FlowMap-Brox-M-frame' then
      meanstd = {mean = { 0.951, 0.918, 0.955 },
                  std = { 0.043, 0.052, 0.044 }}
   end

   local scaleSize, imageSize = 256, 224
   if opt.downsample ~='false' then -- downsample to half
      scaleSize = scaleSize / 2
      imageSize = imageSize / 2
   end

   if self.split == 'train' then
      return t.Compose{
         t.RandomSizedCrop(imageSize),
         -- t.ColorJitter({
         --    brightness = 0.4,
         --    contrast = 0.4,
         --    saturation = 0.4,
         -- }),
         t.ColorNormalize(meanstd,opt.nChannel),
         t.HorizontalFlip(0.5),
      }
   elseif self.split == 'val' then
      local Crop = self.opt.tenCrop and t.TenCrop or t.CenterCrop
      return t.Compose{
         t.Scale(scaleSize),
         t.ColorNormalize(meanstd,opt.nChannel),
         Crop(imageSize),
      }
   else
      error('invalid split: ' .. self.split)
   end
end

return M.UCF101Dataset
