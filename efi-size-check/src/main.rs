#![no_main]
#![no_std]

extern crate alloc;
extern crate uefi;
extern crate uefi_services;

use alloc::format;
use alloc::string::String;
use alloc::vec::Vec;
use log::info;
use uefi::prelude::*;
use uefi::proto::media::file::{File, FileAttribute, FileMode};
use uefi::table::boot::{AllocateType, MemoryType};
use uefi::CStr16;

const KB: usize = 1024;
const MB: usize = KB * 1024;
const GB: usize = MB * 1024;

const MAX_SIZE: usize = 2 * GB;
const INCREMENT: usize = 100 * MB;

#[entry]
fn main(image: Handle, mut st: SystemTable<Boot>) -> Status {
    match uefi_services::init(&mut st) {
        Ok(_) => {}
        Err(err) => {
            panic!("Failed to initialize uefi services: {:?}", err);
        }
    }
    info!("Starting EFI size checker...");

    let bs = st.boot_services();

    let mut sfs = bs.get_image_file_system(image).unwrap();
    let mut root = sfs.open_volume().unwrap();

    let mut buf = [0; 4];
    let file_name: &CStr16 = CStr16::from_str_with_buf("ABC", &mut buf).unwrap(); // Ensure this file exists on your ESP with a large size for testing
    let mut buffer_size = MB * 100; // Start with 100 MiB
    info!("start to do file read check...");

    loop {
        if buffer_size > MAX_SIZE {
            info!("Max buffer size reached: {}", format_bytes(MAX_SIZE));
            break;
        }
        let mut file = match root.open(file_name, FileMode::Read, FileAttribute::empty()) {
            Ok(f) => f.into_regular_file().unwrap(),
            Err(_) => {
                panic!("Failed to open file: {:?}", file_name);
            }
        };

        info!("Reading {} bytes into buffer", format_bytes(buffer_size));

        let mut buffer = Vec::with_capacity(buffer_size);
        unsafe {
            buffer.set_len(buffer_size);
        } // Unsafe due to uninitialized memory

        match file.read_unchunked(&mut buffer) {
            Ok(_) => {
                info!(
                    "Successfully read {} into buffer",
                    format_bytes(buffer_size)
                );
                buffer_size += INCREMENT;
            }
            Err(e) => {
                panic!("Failed to read into a {} byte buffer: {:?}", buffer_size, e);
            }
        }
    }

    mem_test(bs);

    bs.stall(100_000_000);
    Status::SUCCESS
}

fn mem_test(bs: &BootServices) {
    let mut buffer_size = MB * 100; // Start with 100 MiB
    info!("start to do memory allocation check...");

    loop {
        if buffer_size > MAX_SIZE {
            info!("Max buffer size reached: {}", format_bytes(MAX_SIZE));
            break;
        }
        match bs.allocate_pages(
            AllocateType::AnyPages,
            MemoryType::ACPI_RECLAIM,
            buffer_size,
        ) {
            Ok(addr) => {
                info!("Successfully allocated {} mem", buffer_size);
                unsafe {
                    match bs.free_pages(addr, buffer_size) {
                        Ok(_) => {
                            info!("Successfully freed {} mem", buffer_size)
                        }
                        Err(err) => {
                            panic!("Failed to free {} mem: {:?}", buffer_size, err);
                        }
                    }
                }
            }
            Err(err) => {
                panic!("Failed to allocate {} mem: {:?}", buffer_size, err);
            }
        }
        buffer_size += INCREMENT;
    }
}

fn format_bytes(size: usize) -> String {
    if size >= GB {
        format!("{:.2} GB", size as f64 / GB as f64)
    } else if size >= MB {
        format!("{:.2} MB", size as f64 / MB as f64)
    } else if size >= KB {
        format!("{:.2} KB", size as f64 / KB as f64)
    } else {
        format!("{} bytes", size)
    }
}