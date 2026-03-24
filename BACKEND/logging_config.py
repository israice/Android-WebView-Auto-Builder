"""Centralized logging configuration for Android-WebView-Auto-Builder.

This module provides a consistent logging setup across all application modules,
with configurable log levels, formatters, and output handlers.

Example:
    from BACKEND.logging_config import setup_logging, get_logger

    setup_logging(level=logging.DEBUG)
    logger = get_logger(__name__)
    logger.info("Application started")
"""

import logging
import sys
from typing import Optional, List


def setup_logging(
    level: int = logging.INFO,
    log_file: Optional[str] = None,
    log_format: Optional[str] = None
) -> None:
    """Configure application-wide logging.

    Sets up logging with consistent formatting across all modules.
    Can output to stdout and optionally to a file.

    Args:
        level: Logging level (default: logging.INFO)
        log_file: Optional path to log file for persistent logging
        log_format: Optional custom format string

    Example:
        setup_logging(level=logging.DEBUG, log_file='app.log')
    """
    if log_format is None:
        log_format = '%(asctime)s - %(name)s - %(levelname)s - %(message)s'

    handlers: List[logging.Handler] = [logging.StreamHandler(sys.stdout)]

    if log_file:
        file_handler = logging.FileHandler(log_file, encoding='utf-8')
        handlers.append(file_handler)

    logging.basicConfig(
        level=level,
        format=log_format,
        handlers=handlers,
        force=True  # Reset any existing configuration
    )

    # Reduce noise from third-party libraries
    logging.getLogger('uvicorn').setLevel(logging.WARNING)
    logging.getLogger('urllib3').setLevel(logging.WARNING)


def get_logger(name: str) -> logging.Logger:
    """Get a logger instance for the specified module.

    Args:
        name: Logger name, typically __name__ of the calling module

    Returns:
        Configured logger instance

    Example:
        logger = get_logger(__name__)
        logger.info("Processing started")
    """
    return logging.getLogger(name)
