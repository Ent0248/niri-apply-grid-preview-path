#!/bin/bash


VERSION=$(grep '^version' Cargo.toml | head -1 | cut -d '"' -f2)
if [[ "$VERSION" != "25.11.0" ]]; then
    echo -en "\033[1;33m该补丁是25.11.0版本编写的,当前版本:\033[1;31m$VERSION\033[1;33m 是否继续?(y/n)\033[0m"
    read input
    if [[ "$input" != "y" ]]; then
        exit
    fi
fi


# 固定预览时的水平滑动
sed -i '/fn compute_view_pos(&self) -> f64 {/,/^    }/c\
    fn compute_view_pos(&self) -> f64 {\
        0.0\
    }' src/ui/mru.rs

# 网格预览
sed -i '/fn thumbnails(&self) -> impl Iterator/,/^    }/c\
    fn thumbnails(&self) -> impl Iterator<Item = (&Thumbnail, Rectangle<f64, Logical>)> {\
        let thumbnails: Vec<_> = self.wmru.thumbnails().collect();\
        let count = thumbnails.len();\
        if count == 0 {\
            return vec![].into_iter();\
        }\
\
        let output_size = output_size(&self.output);\
        let scale = self.output.current_scale().fractional_scale();\
        let round = move |logical: f64| round_logical_in_physical(scale, logical);\
\
        let config = self.config.borrow();\
        let _padding = round(config.recent_windows.highlight.padding as f64) + round(BORDER);\
        let gap = round(GAP);\
\
        let margin = round(40.0);\
        let max_width = output_size.w - margin * 2.0;\
        let max_height = output_size.h - margin * 2.0;\
\
        let original_sizes: Vec<Size<f64, Logical>> = thumbnails\
            .iter()\
            .map(|t| t.preview_size(output_size, scale))\
            .collect();\
\
        let try_layout = |height_scale: f64| -> Option<(Vec<Vec<usize>>, Vec<Size<f64, Logical>>, f64, f64)> {\
            let max_single_height = max_height.min(300.0); // 单个窗口最大高度限制\
            let current_height = (original_sizes[0].h * height_scale).min(max_single_height);\
\
            let mut scaled_sizes: Vec<Size<f64, Logical>> = original_sizes\
                .iter()\
                .map(|orig| {\
                    let scale_factor = current_height / orig.h;\
                    Size::new(orig.w * scale_factor, current_height)\
                })\
                .collect();\
\
            let mut rows: Vec<Vec<usize>> = Vec::new();\
            let mut current_row = Vec::new();\
            let mut current_row_width = 0.0;\
\
            for i in 0..count {\
                let item_width = scaled_sizes[i].w;\
\
                if current_row.is_empty() {\
                    current_row.push(i);\
                    current_row_width = item_width;\
                } else if current_row_width + gap + item_width <= max_width {\
                    current_row.push(i);\
                    current_row_width += gap + item_width;\
                } else {\
                    rows.push(current_row);\
                    current_row = vec![i];\
                    current_row_width = item_width;\
                }\
            }\
\
            if !current_row.is_empty() {\
                rows.push(current_row);\
            }\
\
            let total_height = rows.len() as f64 * current_height + (rows.len() - 1) as f64 * gap;\
\
            if total_height <= max_height + 1e-6 {\
                Some((rows, scaled_sizes, total_height, current_height))\
            } else {\
                None\
            }\
        };\
\
        let mut best_layout: Option<(Vec<Vec<usize>>, Vec<Size<f64, Logical>>, f64, f64)> = None;\
\
        for percent in (20..=100).rev() {\
            let scale_factor = percent as f64 / 100.0;\
            if let Some(layout) = try_layout(scale_factor) {\
                best_layout = Some(layout);\
                break;\
            }\
        }\
\
        if best_layout.is_none() {\
            for percent in (10..20).rev() {\
                let scale_factor = percent as f64 / 100.0;\
                if let Some(layout) = try_layout(scale_factor) {\
                    best_layout = Some(layout);\
                    break;\
                }\
            }\
        }\
\
        let (rows, scaled_sizes, total_height, row_height) = best_layout.unwrap_or_else(|| {\
            let min_height = 50.0;\
            let mut scaled_sizes: Vec<Size<f64, Logical>> = original_sizes\
                .iter()\
                .map(|orig| {\
                    let scale_factor = min_height / orig.h;\
                    Size::new(orig.w * scale_factor, min_height)\
                })\
                .collect();\
\
            let mut rows: Vec<Vec<usize>> = Vec::new();\
            let mut current_row = Vec::new();\
            let mut current_row_width = 0.0;\
\
            for i in 0..count {\
                let item_width = scaled_sizes[i].w;\
\
                if current_row.is_empty() {\
                    current_row.push(i);\
                    current_row_width = item_width;\
                } else if current_row_width + gap + item_width <= max_width {\
                    current_row.push(i);\
                    current_row_width += gap + item_width;\
                } else {\
                    rows.push(current_row);\
                    current_row = vec![i];\
                    current_row_width = item_width;\
                }\
            }\
\
            if !current_row.is_empty() {\
                rows.push(current_row);\
            }\
\
            let total_height = rows.len() as f64 * min_height + (rows.len() - 1) as f64 * gap;\
            (rows, scaled_sizes, total_height, min_height)\
        });\
\
        let row_count = rows.len();\
        let row_heights = vec![row_height; row_count];\
\
        let start_y = (output_size.h - total_height) / 2.0;\
\
        let mut y_offsets = vec![0.0_f64; row_count];\
        for row in 0..row_count {\
            y_offsets[row] = start_y + row_heights[0..row].iter().sum::<f64>() + row as f64 * gap;\
        }\
\
        let mut result = Vec::with_capacity(count);\
\
        for (row_idx, row_indices) in rows.iter().enumerate() {\
            let row_total_width: f64 = row_indices\
                .iter()\
                .map(|&idx| scaled_sizes[idx].w)\
                .sum::<f64>()\
                + (row_indices.len() - 1) as f64 * gap;\
\
            let start_x = (output_size.w - row_total_width) / 2.0;\
\
            let mut x_offset = start_x;\
            for &idx in row_indices {\
                let size = scaled_sizes[idx];\
                let loc = Point::new(round(x_offset), round(y_offsets[row_idx]));\
                result.push((thumbnails[idx], Rectangle::new(loc, size)));\
                x_offset += size.w + gap;\
            }\
        }\
\
        result.into_iter()\
    }' src/ui/mru.rs


