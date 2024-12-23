use axum::{routing::get, Router};
use std::net::SocketAddr;

#[tokio::main]
async fn main() {
    // Build the router
    let app = Router::new().route("/status", get(status_handler));

    // Define the address to run the server
    let addr = SocketAddr::from(([127, 0, 0, 1], 3000));
    println!("Server running on {}", addr);

    // Start the server
    axum_server::bind(addr)
        .serve(app.into_make_service())
        .await
        .unwrap();
}

// Handler for the `/status` endpoint
async fn status_handler() -> &'static str {
    "ok"
}
