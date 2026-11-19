"""Finder layout for the AetherNX installer disk image."""
from pathlib import Path

inputs = globals()['defines']
app = Path(inputs['app'])
files = [str(app)]
symlinks = {'Applications': '/Applications'}
icon = str(Path(inputs['icon']))
background = str(Path(inputs['background']))
format = 'UDZO'

window_rect = ((180, 160), (720, 440))
default_view = 'icon-view'
show_toolbar = False
show_status_bar = False
show_sidebar = False
show_pathbar = False
arrange_by = None
icon_size = 100
text_size = 14
icon_locations = {app.name: (202, 232), 'Applications': (520, 232)}
