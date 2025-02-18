module Technoweenie # :nodoc:
  module AttachmentFu # :nodoc:
    module Processors
      module MiniMagickProcessor
        def self.included(base)
          base.send :extend, ClassMethods
          #base.send :alias_method, :process_attachment_without_processing, :process_attachment
          #base.send :alias_method, :process_attachment, :process_attachment_with_processing
        end
 
        module ClassMethods
          # Yields a block containing an MiniMagick Image for the given binary data.
          def with_image(file, &block)
            begin
              binary_data = file.is_a?(MiniMagick::Image) ? file : MiniMagick::Image.open(file) unless !Object.const_defined?(:MiniMagick)
            rescue
              # Log the failure to load the image.
              logger.debug("Exception working with image: #{$!}")
              binary_data = nil
            end
            block.call binary_data if block && binary_data
          ensure
            !binary_data.nil?
          end
        end
 
      protected
        def process_attachment
          return unless process_attachment_without_processing
          with_image do |img|
            resize_image_or_thumbnail! img
            self.width = img[:width] if respond_to?(:width)
            self.height = img[:height] if respond_to?(:height)
            callback_with_args :after_resize, img
          end if image?
        end
 
        # Performs the actual resizing operation for a thumbnail
        def resize_image(img, size)
          size = size.first if size.is_a?(Array) && size.length == 1
          format = img[:format]
          img.combine_options do |commands|
            commands.strip unless attachment_options[:keep_profile]

            # GIF is not handled correctly, so we move to PNG, as in other processors…
            if format == 'GIF'
              img.format('PNG')
            end
            
            if size.is_a?(Integer) || (size.is_a?(Array) && size.first.is_a?(Integer))
              if size.is_a?(Integer)
                size = [size, size]
                commands.resize(size.join('x'))
              else
                commands.resize(size.join('x') + '!')
              end
            # extend to thumbnail size
            elsif size.is_a?(String) and size =~ /e$/
              size = size.gsub(/e/, '')
              commands.resize(size.to_s + '>')
              commands.background('#ffffff')
              commands.gravity('center')
              commands.extent(size)
            # crop thumbnail, the smart way
            elsif size.is_a?(String) and size =~ /c$/
               size = size.gsub(/c/, '')
              
              # calculate sizes and aspect ratio
              thumb_width, thumb_height = size.split("x")
              thumb_width   = thumb_width.to_f
              thumb_height  = thumb_height.to_f
              
              thumb_aspect = thumb_width.to_f / thumb_height.to_f
              image_width, image_height = img[:width].to_f, img[:height].to_f
              image_aspect = image_width / image_height
              
              # only crop if image is not smaller in both dimensions
              unless image_width < thumb_width and image_height < thumb_height
                command = calculate_offset(image_width,image_height,image_aspect,thumb_width,thumb_height,thumb_aspect)

                # crop image
                commands.extract(command)
              end

              # don not resize if image is not as height or width then thumbnail
              if image_width < thumb_width or image_height < thumb_height                   
                  commands.background('#ffffff')
                  commands.gravity('center')
                  commands.extent(size)
              # resize image
              else
                commands.resize("#{size.to_s}")
              end
            # crop end
            else
              commands.resize(size.to_s)
            end
          end
          dims = img[:dimensions]
          self.width  = dims[0] if respond_to?(:width)
          self.height = dims[1] if respond_to?(:height)
          # Has to be done this far so we get proper dimensions
          if format == 'JPEG'
            quality = get_jpeg_quality
            img.quality(quality) if quality
          end
          temp_paths.unshift img
          self.size = File.size(self.temp_path)
        end

        def calculate_offset(image_width,image_height,image_aspect,thumb_width,thumb_height,thumb_aspect)
        # only crop if image is not smaller in both dimensions

          # special cases, image smaller in one dimension then thumbsize
          if image_width < thumb_width
            offset = (image_height / 2) - (thumb_height / 2)
            command = "#{image_width}x#{thumb_height}+0+#{offset}"
          elsif image_height < thumb_height
            offset = (image_width / 2) - (thumb_width / 2)
            command = "#{thumb_width}x#{image_height}+#{offset}+0"

          # normal thumbnail generation
          # calculate height and offset y, width is fixed                 
          elsif (image_aspect <= thumb_aspect or image_width < thumb_width) and image_height > thumb_height
            height = image_width / thumb_aspect
            offset = (image_height / 2) - (height / 2)
            command = "#{image_width}x#{height}+0+#{offset}"
          # calculate width and offset x, height is fixed
          else
            width = image_height * thumb_aspect
            offset = (image_width / 2) - (width / 2)
            command = "#{width}x#{image_height}+#{offset}+0"
          end
          # crop image
          command
        end


      end
    end
  end
end
