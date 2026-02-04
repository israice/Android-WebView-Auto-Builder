import re
import os
import logging

logger = logging.getLogger(__name__)


def sync_version():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    root_dir = os.path.dirname(script_dir)

    version_file = os.path.join(root_dir, 'VERSION.md')
    html_file = os.path.join(root_dir, 'templates', 'index.html')

    # Read VERSION.md and get last line version
    with open(version_file, 'r', encoding='utf-8') as f:
        lines = [l.strip() for l in f.readlines() if l.strip()]
        last_line = lines[-1]

    match = re.search(r'(v\d+\.\d+\.\d+)', last_line)
    if not match:
        logger.error("No version found in VERSION.md")
        return
    new_version = match.group(1)

    # Read HTML and find current version-badge
    with open(html_file, 'r', encoding='utf-8') as f:
        html_content = f.read()

    badge_pattern = r'(<button class="version-badge">)(v[\d.]+)(</button>)'
    badge_match = re.search(badge_pattern, html_content)

    if not badge_match:
        logger.error("version-badge not found in index.html")
        return

    current_version = badge_match.group(2)

    if current_version == new_version:
        logger.info(f"Version already up to date: {current_version}")
        return

    # Update HTML
    new_html = re.sub(badge_pattern, f'\\g<1>{new_version}\\g<3>', html_content)
    with open(html_file, 'w', encoding='utf-8') as f:
        f.write(new_html)

    logger.info(f"Updated version: {current_version} -> {new_version}")

if __name__ == '__main__':
    sync_version()
