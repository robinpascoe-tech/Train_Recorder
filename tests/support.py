from importlib.util import module_from_spec, spec_from_file_location
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def load_script_module(relative_path: str, module_name: str):
    path = ROOT / relative_path
    spec = spec_from_file_location(module_name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load module from {path}")
    module = module_from_spec(spec)
    spec.loader.exec_module(module)
    return module
