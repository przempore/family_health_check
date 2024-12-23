use clap::Parser;
use ffmpeg_next as ffmpeg;
use image::{RgbImage, ImageBuffer};
use std::path::Path;

/// Command-line arguments
#[derive(Parser)]
#[command(author, version, about, long_about = None)]
struct Args {
    /// Path to the input video file
    input: String,

    /// Optional path to the output image file (default: thumbnail.jpg)
    #[arg(short, long, default_value = "thumbnail.jpg")]
    output: String,
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Parse command-line arguments
    let args = Args::parse();

    // Initialize FFmpeg
    ffmpeg::init()?;

    // Open the input file
    let mut ictx = ffmpeg::format::input(&args.input)?;

    // Find the best video stream
    let input = ictx
        .streams()
        .best(ffmpeg::media::Type::Video)
        .ok_or("No video stream found")?;

    let stream_index = input.index();
    let codec = ffmpeg::codec::context::Context::from_parameters(input.parameters())?;
    let mut decoder = codec.decoder().video()?;

    // Seek to 10 seconds
    ictx.seek(10_000_000, ..)?;

    let mut scaler = ffmpeg::software::scaling::context::Context::get(
        decoder.format(),
        decoder.width(),
        decoder.height(),
        ffmpeg::format::Pixel::RGB24,
        decoder.width(),
        decoder.height(),
        ffmpeg::software::scaling::flag::Flags::BILINEAR,
    )?;

    // Decode and scale frames
    for (stream, packet) in ictx.packets() {
        if stream.index() == stream_index {
            decoder.send_packet(&packet)?;

            let mut frame = ffmpeg::util::frame::video::Video::empty();
            if decoder.receive_frame(&mut frame).is_ok() {
                let mut rgb_frame = ffmpeg::util::frame::video::Video::empty();
                scaler.run(&frame, &mut rgb_frame)?;

                // Create an ImageBuffer from the scaled frame
                let buffer: Vec<u8> = rgb_frame.data(0).iter().cloned().collect();
                let img: RgbImage = ImageBuffer::from_raw(
                    rgb_frame.width(),
                    rgb_frame.height(),
                    buffer,
                ).ok_or("Failed to create image buffer")?;

                // Save the image as a file
                img.save(Path::new(&args.output))?;
                println!("Thumbnail saved to {}", args.output);

                break;
            }
        }
    }

    Ok(())
}
