"""Adapters: what the system says, parsed. Each reads through homelab.exec or HTTP.

Every adapter here is read-only. They return plain dataclasses, never MCP
envelopes: the domains (homelab/domains/) decide what's ok, warn or fail.
"""
