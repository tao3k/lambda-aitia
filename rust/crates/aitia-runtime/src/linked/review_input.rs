// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

//! Map linked review facts and results through the bridge’s Scheme types.

use gerbil_scheme::{
    BigIntegerBuffer, BinaryInteger, CollectionKind, GerbilRuntime, IdentifierBuffer, NativeError,
    ObjectKind, RootedObjectBatch, RootedSchemeObject, SchemeScalar, TableEquality,
};
use serde_json::{Number, Value};

pub(super) fn to_scheme<'vm>(
    runtime: &'vm GerbilRuntime,
    value: &Value,
) -> Result<RootedSchemeObject<'vm>, NativeError> {
    match value {
        Value::Null => runtime.void_object(),
        Value::Bool(value) => runtime.scalar_object(SchemeScalar::Boolean(*value)),
        Value::Number(value) => number(runtime, value),
        Value::String(value) => Ok(runtime.string_from_utf8(value)?.into_object()),
        Value::Array(items) => {
            let items = items
                .iter()
                .map(|item| to_scheme(runtime, item))
                .collect::<Result<Vec<_>, _>>()?;
            let roots = items.iter().collect::<Vec<_>>();
            Ok(runtime
                .collection_from_objects(CollectionKind::List, &roots)?
                .into_object())
        }
        Value::Object(fields) => {
            let fields = fields
                .iter()
                .map(|(key, value)| {
                    Ok((
                        runtime.string_from_utf8(key)?.into_object(),
                        to_scheme(runtime, value)?,
                    ))
                })
                .collect::<Result<Vec<_>, NativeError>>()?;
            let roots = fields
                .iter()
                .map(|(key, value)| (key, value))
                .collect::<Vec<_>>();
            runtime.gerbil_hash_table(TableEquality::Structural, &roots)
        }
    }
}

fn number<'vm>(
    runtime: &'vm GerbilRuntime,
    value: &Number,
) -> Result<RootedSchemeObject<'vm>, NativeError> {
    let (negative, magnitude) = if let Some(integer) = value.as_i64() {
        if let Ok(fixnum) = i32::try_from(integer) {
            return runtime.scalar_object(SchemeScalar::Fixnum(fixnum as isize));
        }
        (integer < 0, integer.unsigned_abs())
    } else if let Some(integer) = value.as_u64() {
        (false, integer)
    } else {
        let float = value.as_f64().expect("finite serde_json number");
        return runtime.scalar_object(SchemeScalar::Flonum(float));
    };
    let bytes = magnitude.to_le_bytes();
    let length = (u64::BITS - magnitude.leading_zeros()).div_ceil(8) as usize;
    runtime.big_integer(&BinaryInteger::new(negative, bytes[..length].to_vec())?)
}

pub(super) fn from_scheme(value: RootedSchemeObject<'_>) -> Result<Value, NativeError> {
    let reference = value.as_ref();
    match reference.kind()? {
        ObjectKind::Void => Ok(Value::Null),
        ObjectKind::Boolean => match reference.scalar()? {
            SchemeScalar::Boolean(flag) => Ok(Value::Bool(flag)),
            _ => Err(invalid_review_result()),
        },
        ObjectKind::ExactInteger => {
            if let Ok(SchemeScalar::Fixnum(number)) = reference.scalar() {
                return Ok(Value::from(number));
            }
            let mut buffer = BigIntegerBuffer::default();
            reference.copy_big_integer(&mut buffer)?;
            let number = buffer.value();
            let mut magnitude = [0; 8];
            magnitude
                .get_mut(..number.magnitude().len())
                .ok_or_else(invalid_review_result)?
                .copy_from_slice(number.magnitude());
            let magnitude = u64::from_le_bytes(magnitude);
            if number.is_negative() {
                i64::try_from(-i128::from(magnitude))
                    .map(Value::from)
                    .map_err(|_| invalid_review_result())
            } else {
                Ok(Value::from(magnitude))
            }
        }
        ObjectKind::String => Ok(Value::String(
            value.into_string()?.to_string().into_result()?,
        )),
        ObjectKind::Symbol | ObjectKind::Keyword => {
            let mut names = IdentifierBuffer::default();
            reference.copy_identifier_names(&mut names)?;
            let (_, name) = names.get(0).ok_or_else(invalid_review_result)?;
            Ok(Value::String(name.to_owned()))
        }
        ObjectKind::Vector => {
            let vector = value.into_collection(CollectionKind::Vector)?;
            (0..vector.len())
                .map(|index| from_scheme(vector.element(index)?))
                .collect::<Result<Vec<_>, _>>()
                .map(Value::Array)
        }
        ObjectKind::GerbilHashTable | ObjectKind::GambitTable => {
            let mut entries = RootedObjectBatch::default();
            value.copy_table_entries(&mut entries)?;
            let mut object = serde_json::Map::new();
            for index in (0..entries.len()).step_by(2) {
                let Value::String(key) = from_scheme(entries.root_element(index)?)? else {
                    return Err(invalid_review_result());
                };
                if object
                    .insert(key, from_scheme(entries.root_element(index + 1)?)?)
                    .is_some()
                {
                    return Err(invalid_review_result());
                }
            }
            Ok(Value::Object(object))
        }
        _ => Err(invalid_review_result()),
    }
}

fn invalid_review_result() -> NativeError {
    NativeError::Status {
        operation: "project linked commit review result",
        code: gerbil_scheme_sys::GerbilStatus::InvalidValue as i32,
    }
}
