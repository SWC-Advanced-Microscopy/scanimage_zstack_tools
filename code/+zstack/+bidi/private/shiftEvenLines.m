function shiftOut = shiftEvenLines(img, shiftAmt)
     [r,c] = size(img);
     out = img;
     for i = 1:r
          if ~mod(i, 2) % if 0 then even line
               out(i,:) = circshift(img(i, :), shiftAmt);
          end
     end
    shiftOut = out;
end
