# WSGI entrypoint for Gunicorn
from webapp.api import create_app

app = create_app()