"""Read-only incident correlation and RCA for the SRE platform."""

from .engine import analyze
from .model import Incident, SignalSnapshot

__all__ = ["Incident", "SignalSnapshot", "analyze"]