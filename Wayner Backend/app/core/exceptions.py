class FerrotiendaError(Exception):
    pass


class DatabaseConnectionError(FerrotiendaError):
    pass


class NotFoundError(FerrotiendaError):
    pass


class ValidationError(FerrotiendaError):
    pass
