"""Command-line interface for Mongython."""

import argparse
import sys
import uvicorn


def serve_command(args):
    """Start the API server."""
    print(f"Starting Mongython API server on {args.host}:{args.port}")

    uvicorn.run(
        "mongython.api:app",
        host=args.host,
        port=args.port,
        reload=args.reload,
        log_level=args.log_level.lower(),
    )


def main():
    """Main entry point for the CLI."""
    parser = argparse.ArgumentParser(
        description="Mongython - MongoDB Python API", prog="mongython"
    )
    subparsers = parser.add_subparsers(dest="command", help="Command to run")

    # Serve command
    serve_parser = subparsers.add_parser("serve", help="Start the API server")
    serve_parser.add_argument(
        "--port",
        type=int,
        default=8088,
        help="Port to run the server on (default: 8088)",
    )
    serve_parser.add_argument(
        "--host",
        type=str,
        default="0.0.0.0",
        help="Host to run the server on (default: 0.0.0.0)",
    )
    serve_parser.add_argument(
        "--reload", action="store_true", help="Enable auto-reload for development"
    )
    serve_parser.add_argument(
        "--log-level",
        type=str,
        default="INFO",
        choices=["DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"],
        help="Logging level (default: INFO)",
    )
    serve_parser.set_defaults(func=serve_command)

    # Parse args
    args = parser.parse_args()

    if not args.command:
        parser.print_help()
        sys.exit(1)

    args.func(args)


if __name__ == "__main__":
    main()
