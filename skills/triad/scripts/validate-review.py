"""Validate Triad's review schemas and cross-round gate invariants (stdlib only)."""

import json
import sys


def require(condition, message):
    if not condition:
        raise ValueError(message)


def validate(value, schema, path="$ review"):
    types = {"object": dict, "array": list, "string": str,
             "boolean": bool, "integer": int}
    require(type(value) is types[schema["type"]], f"{path}: wrong type")
    if "enum" in schema:
        require(value in schema["enum"], f"{path}: invalid value")
    if isinstance(value, dict):
        require(set(schema.get("required", [])) <= value.keys(),
                f"{path}: missing required fields")
        properties = schema["properties"]
        if schema.get("additionalProperties") is False:
            require(value.keys() <= properties.keys(), f"{path}: unknown fields")
        for key, item in value.items():
            validate(item, properties[key], f"{path}.{key}")
    elif isinstance(value, list):
        for index, item in enumerate(value):
            validate(item, schema["items"], f"{path}[{index}]")


def ids(items):
    result = [item["id"] for item in items]
    require(all(item.strip() for item in result), "empty finding id")
    require(len(set(result)) == len(result), "duplicate finding id")
    return set(result)


def check(review, previous, schema):
    validate(review, schema)
    key = "gaps" if "gaps" in schema["properties"] else "findings"
    passing = "approved" if key == "gaps" else "clean"
    current_ids = ids(review[key])
    resolved_ids = ids(review["resolved_previous"])
    previous_ids = set()
    if previous is not None:
        validate(previous, schema)
        previous_ids = ids(previous[key])
        previous_ids |= {item["id"] for item in previous["resolved_previous"]
                         if not item["resolved"]}
    require(resolved_ids == previous_ids,
            "resolved_previous must cover exactly all previous open findings")
    for item in review["resolved_previous"]:
        require((item["id"] not in current_ids) == item["resolved"],
                f"{item['id']}: unresolved findings must be re-raised; resolved findings must be absent")
    if review["verdict"] == passing:
        require(not current_ids and all(item["resolved"] for item in review["resolved_previous"]),
                "passing verdict has open findings")
    else:
        require(bool(current_ids), "non-passing verdict needs findings")
    for item in review.get("findings", []):
        require(item["line"] >= 0, "finding line must be nonnegative")


def read(path):
    with open(path, encoding="utf-8") as source:
        return json.load(source)


if __name__ == "__main__":
    try:
        schema_path, output_path, previous_path = sys.argv[1:]
        check(read(output_path), read(previous_path) if previous_path else None,
              read(schema_path))
    except (ValueError, KeyError, OSError) as error:
        sys.exit(f"triad: invalid review: {error}")
