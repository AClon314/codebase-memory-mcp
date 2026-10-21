def py_a() -> str:
    return py_b()


def py_b() -> str:
    return "b"


def py_entry() -> str:
    fn = py_a
    return fn()
