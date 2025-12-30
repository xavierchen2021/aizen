//
//  TaskItem+Extension.swift
//  aizen
//
//  Created by aizen on 2024-12-30.
//

import Foundation

extension TaskItem {
    /// 默认 Markdown 模板
    static let defaultMarkdownTemplate = """
{prefix}

## {title}

### 描述
{description}

### 资源
{resources}
"""
    
    /// 将任务转换为 Markdown 格式
    func toMarkdown() -> String {
        // 使用自定义模板或默认模板
        let template = markdownTemplate?.isEmpty == false ? markdownTemplate! : TaskItem.defaultMarkdownTemplate
        
        // 准备替换变量
        var result = template
        
        // 替换变量
        result = result.replacingOccurrences(of: "{prefix}", with: customPrefix ?? "")
        result = result.replacingOccurrences(of: "{title}", with: title ?? "")
        result = result.replacingOccurrences(of: "{description}", with: taskDescription ?? "")
        result = result.replacingOccurrences(of: "{resources}", with: resources ?? "")
        
        // 清理多余的空行
        result = result.replacingOccurrences(of: "\n\n\n+", with: "\n\n", options: NSString.CompareOptions.regularExpression)
        result = result.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        
        return result
    }
}
